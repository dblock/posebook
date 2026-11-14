# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DrawingSession, :aggregate_failures, :database do
  it 'defaults slugs from names and retains history when changing or clearing a custom slug' do
    drawing_session = create_drawing_session(name: "Enoch's Drawing")
    expect(drawing_session.slug).to eq('enochs-drawing')
    drawing_session.update!(custom_slug: ' Weekly Life Drawing ')
    expect(drawing_session.slug).to eq('weekly-life-drawing')
    drawing_session.update!(name: "Enoch's Renamed")
    expect(drawing_session.slug).to eq('weekly-life-drawing')
    drawing_session.update!(custom_slug: '')
    expect(drawing_session.slug).to eq('enochs-renamed')
    %w[enochs-drawing weekly-life-drawing enochs-renamed].each do |slug|
      expect(described_class.find(slug)).to eq(drawing_session)
    end
    expect(described_class.find(drawing_session.id)).to eq(drawing_session)
  end

  it 'adds suffixes to duplicate, reserved, and database-ID-shaped slugs' do
    first = create_drawing_session(name: 'Shared Session')
    duplicate = create_drawing_session(name: 'Shared Session')
    reserved = create_drawing_session(custom_slug: 'sessions')
    id_shaped = create_drawing_session(custom_slug: first.id.to_s)
    expect([first.slug, duplicate.slug, reserved.slug]).to eq(%w[shared-session shared-session-1 sessions-1])
    expect(id_shaped.slug).to eq("#{first.id}-1")
    expect(described_class.find(id_shaped.slug)).to eq(id_shaped)
  end

  it 'rejects sources that cannot produce a usable slug' do
    drawing_session = create_drawing_session
    expect(drawing_session.update(custom_slug: '!!!')).to be(false)
    expect(drawing_session.errors[:custom_slug]).to include('must include a letter or number')
    expect(drawing_session.update(name: '!!!', custom_slug: '')).to be(false)
    expect(drawing_session.update(custom_slug: 'x' * 101)).to be(false)
  end

  it 'enforces uniqueness across slug history in MongoDB' do
    drawing_session = create_drawing_session
    other = create_drawing_session
    old_slug = drawing_session.slug
    drawing_session.update!(custom_slug: 'new-unique-slug')
    expect { other.set(_slugs: [old_slug]) }.to raise_error(Mongo::Error::OperationFailure)
  end

  it 'validates session configuration and stores model pay without floating-point rounding' do
    drawing_session = create_drawing_session(model_pay: '140.35', time_zone: 'America/New_York')
    expect(drawing_session.reload.model_pay).to eq(BigDecimal('140.35'))
    drawing_session.assign_attributes(time_zone: 'not/a/zone', booking_horizon_months: 0, model_pay: -1)
    expect(drawing_session).not_to be_valid
    expect(drawing_session.errors.attribute_names).to include(:time_zone, :booking_horizon_months, :model_pay)
  end

  it 'stores organizer access per session without granting global privileges' do
    drawing_session = create_drawing_session
    other = create_drawing_session
    user = create_user
    grant_coordinator_access(drawing_session, user)
    expect(described_class.visible_to(user).to_a).to eq([drawing_session])
    expect(described_class.visible_to(user)).not_to include(other)
    expect(user.reload).not_to be_system_admin
  end

  it 'grants concurrent requests only one membership and one role' do
    drawing_session = create_drawing_session
    user = create_user
    threads = 2.times.map { Thread.new { DrawingSessionMembership.grant_coordinator_access(drawing_session, user) } }
    memberships = DrawingSessionMembership.where(drawing_session_id: drawing_session.id, user_id: user.id)
    begin
      threads.each(&:value)
    ensure
      memberships.each { |membership| track_record(membership) }
    end
    expect(memberships.count).to eq(1)
    expect(memberships.first.roles).to eq(['session_coordinator'])
  end

  it 'enforces membership uniqueness in MongoDB and rejects unsupported roles' do
    drawing_session = create_drawing_session
    user = create_user
    grant_coordinator_access(drawing_session, user)
    expect { DrawingSessionMembership.create!(drawing_session: drawing_session, user: user) }.to raise_error(Mongo::Error::OperationFailure)
    expect(DrawingSessionMembership.new(drawing_session: drawing_session, user: user,
                                        roles: ['system_admin'])).not_to be_valid
  end
end
