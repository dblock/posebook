# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  def attempt(venue, user, date)
    described_class.new(venue: venue, user: user).book(date: date)
  rescue described_class::Conflict, described_class::Invalid
    nil
  end

  def track_venue_bookings(venue)
    venue.model_bookings.each { |booking| track_booking(booking) }
  end

  it 'allows a date change six local calendar days before the saved one-off drawing' do
    venue = create_venue
    user = create_user
    grant_model_access(venue, user)
    track_record(VenueScheduleException.create!(venue: venue, date: Date.new(2026, 11, 23), mode: 'open',
                                                start_time: '20:00', reason: 'Later drawing.'))
    original = track_booking(attempt(venue, user, '2026-11-23'))
    travel_to Time.utc(2026, 11, 18, 4, 59, 59)
    replacement = track_booking(described_class.new(venue: venue, user: user)
                                               .change(booking: original, date: '2026-11-30', reason: 'Travel.'))
    expect(replacement.date).to eq(Date.new(2026, 11, 30))
    expect(original.reload.status).to eq('rescheduled')
  end

  it 'rechecks the five-day cutoff at venue-local midnight after a change page was opened' do
    venue = create_venue
    user = create_user
    grant_model_access(venue, user)
    original = track_booking(attempt(venue, user, '2026-11-23'))
    expect(original.rescheduling_locked?).to be(false)
    travel_to Time.utc(2026, 11, 18, 5)
    expect do
      described_class.new(venue: venue, user: user)
                     .change(booking: original, date: '2026-11-30', reason: 'Travel.')
    end.to raise_error(described_class::Invalid, /contact an organizer/)
    expect(original.reload.status).to eq('confirmed')
    expect(venue.model_bookings.count).to eq(1)
    expect(ModelBookingClaim.find_by(model_booking_id: original.id).date).to eq(original.date)
  end

  it 'allows only one model to claim a day and rolls back losing ledger records' do
    venue = create_venue
    users = Array.new(2) { create_user }
    users.each { |user| grant_model_access(venue, user) }
    results = users.map { |user| Thread.new { attempt(venue, user, '2026-11-16') } }.map(&:value)
    track_venue_bookings(venue)
    expect(results.compact.size).to eq(1)
    expect(venue.model_bookings.count).to eq(1)
    expect(ModelBookingClaim.where(venue_id: venue.id).count).to eq(1)
  end

  it 'allows only one upcoming date per model even when two dates are claimed concurrently' do
    venue = create_venue
    user = create_user
    grant_model_access(venue, user)
    results = %w[2026-11-16 2026-11-23].map { |date| Thread.new { attempt(venue, user, date) } }.map(&:value)
    track_venue_bookings(venue)
    expect(results.compact.size).to eq(1)
    expect(venue.model_bookings.count).to eq(1)
    expect(ModelBookingClaim.where(venue_id: venue.id).count).to eq(1)
  end

  it 'releases expired claims without background jobs or deleting historical bookings' do
    venue = create_venue
    user = create_user
    grant_model_access(venue, user)
    first = track_booking(attempt(venue, user, '2026-11-16'))
    travel_to Time.utc(2026, 11, 17, 15)
    expect(attempt(venue, user, '2026-11-23')).to be_nil
    VenueMembership.find_by(venue_id: venue.id, user_id: user.id).update!(booking_invited_at: Time.current)
    second = track_booking(attempt(venue, user, '2026-11-23'))
    expect(first.reload.display_status).to eq('Completed')
    expect(second.date).to eq(Date.new(2026, 11, 23))
    expect(venue.model_bookings.count).to eq(2)
    expect(ModelBookingClaim.where(venue_id: venue.id).count).to eq(1)
  end

  it 'keeps the one-upcoming-booking rule venue-local' do
    user = create_user
    venues = Array.new(2) { create_venue }
    venues.each do |venue|
      grant_model_access(venue, user)
      expect(track_booking(attempt(venue, user, '2026-11-16'))).to be_persisted
    end
    expect(ModelBooking.upcoming.where(user_id: user.id).count).to eq(2)
  end

  it 'preserves booking dates and UTC expiry across daylight saving and venue time-zone edits' do
    travel_to Time.utc(2026, 10, 30, 15)
    venue = create_venue
    user = create_user
    grant_model_access(venue, user)
    booking = track_booking(attempt(venue, user, '2026-11-02'))
    venue.update!(time_zone: 'America/Los_Angeles')
    expect(booking.reload).to have_attributes(date: Date.new(2026, 11, 2), time_zone: 'America/New_York',
                                              ends_at: Time.utc(2026, 11, 3, 5))
  end

  it 'protects retained booking history from model deletion entry points' do
    venue = create_venue
    user = create_user
    grant_model_access(venue, user)
    booking = track_booking(attempt(venue, user, '2026-11-16'))
    booking.destroy
    expect(booking.reload).to be_persisted
    expect { booking.delete }.to raise_error(ModelBooking::HistoryRetained)
    expect { ModelBooking.delete_all }.to raise_error(ModelBooking::HistoryRetained)
    expect(venue.model_bookings.count).to eq(1)
  end
end
