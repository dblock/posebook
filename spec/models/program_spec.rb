# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Program, :aggregate_failures, :database do
  it 'defaults slugs from names and retains history when changing or clearing a custom slug' do
    program = create_program(name: 'Community Workshop')
    expect(program.slug).to eq('community-workshop')
    program.update!(custom_slug: ' Weekly Workshop ')
    expect(program.slug).to eq('weekly-workshop')
    program.update!(name: 'Community Program')
    expect(program.slug).to eq('weekly-workshop')
    program.update!(custom_slug: '')
    expect(program.slug).to eq('community-program')
    %w[community-workshop weekly-workshop community-program].each do |slug|
      expect(described_class.find(slug)).to eq(program)
    end
    expect(described_class.find(program.id)).to eq(program)
  end

  it 'adds suffixes to duplicate, reserved, and database-ID-shaped slugs' do
    first = create_program(name: 'Shared Program')
    duplicate = create_program(name: 'Shared Program')
    reserved = create_program(custom_slug: 'sessions')
    id_shaped = create_program(custom_slug: first.id.to_s)
    expect([first.slug, duplicate.slug, reserved.slug]).to eq(%w[shared-program shared-program-1 sessions-1])
    expect(id_shaped.slug).to eq("#{first.id}-1")
    expect(described_class.find(id_shaped.slug)).to eq(id_shaped)
  end

  it 'rejects sources that cannot produce a usable slug' do
    program = create_program
    expect(program.update(custom_slug: '!!!')).to be(false)
    expect(program.errors[:custom_slug]).to include('must include a letter or number')
    expect(program.update(name: '!!!', custom_slug: '')).to be(false)
    expect(program.update(custom_slug: 'x' * 101)).to be(false)
  end

  it 'enforces uniqueness across slug history in MongoDB' do
    program = create_program
    other = create_program
    old_slug = program.slug
    program.update!(custom_slug: 'new-unique-slug')
    expect { other.set(_slugs: [old_slug]) }.to raise_error(Mongo::Error::OperationFailure)
  end

  it 'validates program configuration and stores participant pay without floating-point rounding' do
    program = create_program(pay: '140.35', time_zone: 'America/New_York')
    expect(program.reload.pay).to eq(BigDecimal('140.35'))
    program.assign_attributes(time_zone: 'not/a/zone', booking_horizon_months: 0, pay: -1)
    expect(program).not_to be_valid
    expect(program.errors.attribute_names).to include(:time_zone, :booking_horizon_months, :pay)
  end

  it 'stores organizer access per program without granting global privileges' do
    program = create_program
    other = create_program
    user = create_user
    grant_coordinator_access(program, user)
    expect(described_class.visible_to(user).to_a).to eq([program])
    expect(described_class.visible_to(user)).not_to include(other)
    expect(user.reload).not_to be_system_admin
  end

  it 'grants concurrent requests only one membership and one role' do
    program = create_program
    user = create_user
    threads = 2.times.map { Thread.new { ProgramMembership.grant_coordinator_access(program, user) } }
    memberships = ProgramMembership.where(program_id: program.id, user_id: user.id)
    begin
      threads.each(&:value)
    ensure
      memberships.each { |membership| track_record(membership) }
    end
    expect(memberships.count).to eq(1)
    expect(memberships.first.roles).to eq(['program_coordinator'])
  end

  it 'enforces membership uniqueness in MongoDB and rejects unsupported roles' do
    program = create_program
    user = create_user
    grant_coordinator_access(program, user)
    expect { ProgramMembership.create!(program: program, user: user) }.to raise_error(Mongo::Error::OperationFailure)
    expect(ProgramMembership.new(program: program, user: user,
                                 roles: ['system_admin'])).not_to be_valid
  end

  it 'normalizes and audits terminology while rejecting blank, oversize, or markup labels' do
    program = create_program
    program.update!(program_label: '  Practice   Group ', participant_label: ' Guest Instructor ')
    expect(program.reload).to have_attributes(program_label: 'Practice Group', participant_label: 'Guest Instructor')
    expect(program.history_tracks.map(&:modified)).to include(
      hash_including('program_label' => 'Practice Group', 'participant_label' => 'Guest Instructor')
    )
    ['', '<script>', 'x' * 41].each do |label|
      expect(program.update(program_label: label, participant_label: label)).to be(false)
      expect(program.errors.attribute_names).to include(:program_label, :participant_label)
      program.reload
    end
  end
end
