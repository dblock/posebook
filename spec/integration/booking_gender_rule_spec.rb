# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingGenderRule, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue(no_consecutive_genders: ['male']) }
  let(:model) { create_user(gender: 'male') }

  before { grant_model_access(venue, model) }

  def reserve(date, gender: 'male', at: venue)
    user = create_user(gender: gender)
    grant_model_access(at, user)
    track_booking(BookingMutation.new(venue: at, user: user).book(date: date))
  end

  def book(date)
    track_booking(BookingMutation.new(venue: venue, user: model).book(date: date))
  end

  def change(original, date)
    track_booking(BookingMutation.new(venue: venue, user: model)
                                .change(booking: original, date: date, reason: 'Travel changed.'))
  end

  def exception(date, mode)
    track_record(VenueScheduleException.create!(venue: venue, date: Date.iso8601(date), mode: mode,
                                                start_time: mode == 'open' ? '18:30' : nil, reason: 'Schedule change.'))
  end

  def attempt(user, date)
    BookingMutation.new(venue: venue, user: user).book(date: date)
  rescue BookingMutation::Invalid
    nil
  end

  User::GENDERS.each do |gender|
    it "independently restricts consecutive #{gender} models when that gender is selected" do
      venue.update!(no_consecutive_genders: [gender])
      model.update!(gender: gender)
      reserve('2026-11-16', gender: gender)
      expect { book('2026-11-23') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
      expect(venue.model_bookings.count).to eq(1)
      venue.update!(no_consecutive_genders: [])
      expect(book('2026-11-23')).to be_persisted
    end
  end

  it 'allows consecutive female models when only male repeats are restricted' do
    reserve('2026-11-16', gender: 'female')
    model.update!(gender: 'female')
    expect(book('2026-11-23')).to be_persisted
  end

  it 'checks the next scheduled session too, including across month boundaries' do
    reserve('2026-12-07')
    expect { book('2026-11-30') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
  end

  it 'does not skip an unbooked session when looking for the preceding model' do
    reserve('2026-11-16')
    expect(book('2026-11-30')).to be_persisted
  end

  it 'skips closures but treats one-off openings as scheduled sessions' do
    reserve('2026-11-16')
    exception('2026-11-23', 'closed')
    expect { book('2026-11-30') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
    exception('2026-11-25', 'open')
    expect(book('2026-11-30')).to be_persisted
  end

  it 'checks completed drawings and their historical one-off schedule' do
    travel_to Time.utc(2026, 11, 6, 15)
    exception('2026-11-12', 'open')
    previous = reserve('2026-11-12')
    travel_to Time.utc(2026, 11, 13, 15)
    expect(previous.display_status).to eq('Completed')
    expect { book('2026-11-16') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
  end

  it 'ignores canceled bookings and bookings at other venues' do
    previous = reserve('2026-11-16')
    BookingMutation.new(venue: venue, user: previous.user).cancel(booking: previous, reason: 'Travel changed.')
    reserve('2026-11-16', at: create_venue)
    expect(book('2026-11-23')).to be_persisted
  end

  it 'excludes the original booking when moving to an adjacent session' do
    original = book('2026-11-23')
    expect(change(original, '2026-11-30').previous_booking_id).to eq(original.id)
    expect(original.reload.status).to eq('rescheduled')
  end

  it 'preserves the original booking and claim after a restricted reschedule' do
    reserve('2026-11-16')
    original = book('2026-11-30')
    expect { change(original, '2026-11-23') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
    expect(original.reload.status).to eq('confirmed')
    expect(ModelBookingClaim.find_by(model_booking_id: original.id).date).to eq(original.date)
    expect(venue.model_bookings.count).to eq(2)
  end

  it 'requires an actual gender selection even when the venue has no restrictions' do
    venue.update!(no_consecutive_genders: [])
    model.update!(gender: nil)
    expect { book('2026-11-16') }.to raise_error(BookingMutation::Invalid, /Select a gender/)
    expect(venue.model_bookings).to be_empty
  end

  it 'reloads the selected gender rather than trusting a stale profile' do
    reserve('2026-11-16')
    model.update!(gender: 'female')
    User.find(model.id).update!(gender: 'male')
    expect { book('2026-11-23') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
  end

  it 'serializes competing adjacent bookings so only one restricted model succeeds' do
    other = create_user(gender: 'male')
    grant_model_access(venue, other)
    results = [model, other].zip(%w[2026-11-16 2026-11-23])
                            .map { |user, date| Thread.new { attempt(user, date) } }.map(&:value)
    venue.model_bookings.each { |booking| track_booking(booking) }
    expect(results.compact.size).to eq(1)
    expect(venue.model_bookings.count).to eq(1)
    expect(ModelBookingClaim.where(venue_id: venue.id).count).to eq(1)
  end
end
