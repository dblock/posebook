# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  def attempt(drawing_session, user, date)
    described_class.new(drawing_session: drawing_session, user: user).book(date: date)
  rescue described_class::Conflict, described_class::Invalid
    nil
  end

  def track_drawing_session_bookings(drawing_session)
    drawing_session.model_bookings.each { |booking| track_booking(booking) }
  end

  it 'allows a date change six local calendar days before the saved one-off drawing' do
    drawing_session = create_drawing_session
    user = create_user
    grant_model_access(drawing_session, user)
    track_record(
      DrawingSessionScheduleException.create!(
        drawing_session: drawing_session, date: Date.new(2026, 11, 23), mode: 'open',
        start_time: '20:00', reason: 'Later drawing.'
      )
    )
    original = track_booking(attempt(drawing_session, user, '2026-11-23'))
    travel_to Time.utc(2026, 11, 18, 4, 59, 59)
    replacement = track_booking(described_class.new(drawing_session: drawing_session, user: user)
                                               .change(booking: original, date: '2026-11-30', reason: 'Travel.'))
    expect(replacement.date).to eq(Date.new(2026, 11, 30))
    expect(original.reload.status).to eq('rescheduled')
  end

  it 'rechecks the five-day cutoff at drawing_session-local midnight after a change page was opened' do
    drawing_session = create_drawing_session
    user = create_user
    grant_model_access(drawing_session, user)
    original = track_booking(attempt(drawing_session, user, '2026-11-23'))
    expect(original.rescheduling_locked?).to be(false)
    travel_to Time.utc(2026, 11, 18, 5)
    expect do
      described_class.new(drawing_session: drawing_session, user: user)
                     .change(booking: original, date: '2026-11-30', reason: 'Travel.')
    end.to raise_error(described_class::Invalid, /contact an organizer/)
    expect(original.reload.status).to eq('confirmed')
    expect(drawing_session.model_bookings.count).to eq(1)
    expect(ModelBookingClaim.find_by(model_booking_id: original.id).date).to eq(original.date)
  end

  it 'allows only one model to claim a day and rolls back losing ledger records' do
    drawing_session = create_drawing_session
    users = Array.new(2) { create_user }
    users.each { |user| grant_model_access(drawing_session, user) }
    results = users.map do |user|
      Thread.new do
        described_class.new(drawing_session: drawing_session, user: user).book(date: '2026-11-16')
      rescue described_class::Conflict => e
        e
      end
    end.map(&:value)
    track_drawing_session_bookings(drawing_session)
    expect(results.grep(ModelBooking).size).to eq(1)
    expect(results.grep(described_class::Conflict).map(&:message)).to eq([I18n.t('bookings.date_taken')])
    expect(drawing_session.model_bookings.count).to eq(1)
    expect(ModelBookingClaim.where(drawing_session_id: drawing_session.id).count).to eq(1)
  end

  it 'allows only one upcoming date per model even when two dates are claimed concurrently' do
    drawing_session = create_drawing_session
    user = create_user
    grant_model_access(drawing_session, user)
    results = %w[2026-11-16 2026-11-23].map { |date| Thread.new { attempt(drawing_session, user, date) } }.map(&:value)
    track_drawing_session_bookings(drawing_session)
    expect(results.compact.size).to eq(1)
    expect(drawing_session.model_bookings.count).to eq(1)
    expect(ModelBookingClaim.where(drawing_session_id: drawing_session.id).count).to eq(1)
  end

  it 'releases expired claims without background jobs or deleting historical bookings' do
    drawing_session = create_drawing_session
    user = create_user
    grant_model_access(drawing_session, user)
    first = track_booking(attempt(drawing_session, user, '2026-11-16'))
    travel_to Time.utc(2026, 11, 17, 15)
    expect(attempt(drawing_session, user, '2026-11-23')).to be_nil
    DrawingSessionMembership.find_by(drawing_session_id: drawing_session.id,
                                     user_id: user.id).update!(booking_invited_at: Time.current)
    second = track_booking(attempt(drawing_session, user, '2026-11-23'))
    expect(first.reload.display_status).to eq('Completed')
    expect(second.date).to eq(Date.new(2026, 11, 23))
    expect(drawing_session.model_bookings.count).to eq(2)
    expect(ModelBookingClaim.where(drawing_session_id: drawing_session.id).count).to eq(1)
  end

  it 'keeps the one-upcoming-booking rule drawing_session-local' do
    user = create_user
    drawing_sessions = Array.new(2) { create_drawing_session }
    drawing_sessions.each do |drawing_session|
      grant_model_access(drawing_session, user)
      expect(track_booking(attempt(drawing_session, user, '2026-11-16'))).to be_persisted
    end
    expect(ModelBooking.upcoming.where(user_id: user.id).count).to eq(2)
  end

  it 'preserves booking dates and UTC expiry across daylight saving and session time-zone edits' do
    travel_to Time.utc(2026, 10, 30, 15)
    drawing_session = create_drawing_session
    user = create_user
    grant_model_access(drawing_session, user)
    booking = track_booking(attempt(drawing_session, user, '2026-11-02'))
    drawing_session.update!(time_zone: 'America/Los_Angeles')
    expect(booking.reload).to have_attributes(date: Date.new(2026, 11, 2), time_zone: 'America/New_York',
                                              ends_at: Time.utc(2026, 11, 3, 5))
  end

  it 'protects retained booking history from model deletion entry points' do
    drawing_session = create_drawing_session
    user = create_user
    grant_model_access(drawing_session, user)
    booking = track_booking(attempt(drawing_session, user, '2026-11-16'))
    booking.destroy
    expect(booking.reload).to be_persisted
    expect { booking.delete }.to raise_error(ModelBooking::HistoryRetained)
    expect { ModelBooking.delete_all }.to raise_error(ModelBooking::HistoryRetained)
    expect(drawing_session.model_bookings.count).to eq(1)
  end
end
