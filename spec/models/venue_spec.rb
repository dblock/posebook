# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Venue, :aggregate_failures, :database do
  it 'validates venue configuration and stores model pay without floating-point rounding' do
    venue = create_venue(model_pay: '140.35', time_zone: 'America/New_York')
    expect(venue.reload.model_pay).to eq(BigDecimal('140.35'))
    venue.assign_attributes(time_zone: 'not/a/zone', booking_horizon_months: 0, model_pay: -1)
    expect(venue).not_to be_valid
    expect(venue.errors.attribute_names).to include(:time_zone, :booking_horizon_months, :model_pay)
  end

  it 'stores organizer access per venue without granting global privileges' do
    venue = create_venue
    other = create_venue
    user = create_user
    grant_schedule_access(venue, user)
    expect(described_class.visible_to(user).to_a).to eq([venue])
    expect(described_class.visible_to(user)).not_to include(other)
    expect(user.reload).not_to be_system_admin
  end

  it 'grants concurrent requests only one membership and one role' do
    venue = create_venue
    user = create_user
    threads = 2.times.map { Thread.new { VenueMembership.grant_schedule_access(venue, user) } }
    memberships = VenueMembership.where(venue_id: venue.id, user_id: user.id)
    begin
      threads.each(&:value)
    ensure
      memberships.each { |membership| track_record(membership) }
    end
    expect(memberships.count).to eq(1)
    expect(memberships.first.roles).to eq(['manage_schedule'])
  end

  it 'enforces membership uniqueness in MongoDB and rejects unsupported roles' do
    venue = create_venue
    user = create_user
    grant_schedule_access(venue, user)
    expect { VenueMembership.create!(venue: venue, user: user) }.to raise_error(Mongo::Error::OperationFailure)
    expect(VenueMembership.new(venue: venue, user: user, roles: ['system_admin'])).not_to be_valid
  end
end
