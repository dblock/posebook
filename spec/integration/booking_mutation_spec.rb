# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  def attempt(program, user, date)
    described_class.new(program: program, user: user).book(date: date)
  rescue described_class::Conflict, described_class::Invalid
    nil
  end

  def track_program_bookings(program)
    program.bookings.each { |booking| track_booking(booking) }
  end

  it 'rejects dates before the cutoff and books the extended horizon immediately' do
    program = create_program(first_bookable_date: Date.new(2027, 1, 1), available_weekdays: %w[0 1 2 3 4 5 6])
    user = create_user
    grant_participant_access(program, user)
    mutation = described_class.new(program: program, user: user)
    %w[2026-12-31 2027-07-02].each do |date|
      expect do
        mutation.book(date: date)
      end.to raise_error(described_class::Invalid, program.message('bookings.invalid_date'))
    end
    expect(program.bookings).to be_empty
    expect(track_booking(mutation.book(date: '2027-07-01')).date).to eq(Date.new(2027, 7, 1))
  end

  it 'rechecks a changed first bookable date and retains the original booking after a rejected reschedule' do
    program = create_program
    user = create_user
    grant_participant_access(program, user)
    original = track_booking(attempt(program, user, '2026-11-23'))
    mutation = described_class.new(program: program, user: user)
    ProgramSettingsUpdate.new(program: program, user: create_user(roles: ['system_admin']))
                         .call(first_bookable_date: '2027-01-01')
    expect { mutation.change(booking: original, date: '2026-12-28', reason: 'Travel.') }
      .to raise_error(described_class::Invalid, program.message('bookings.invalid_date'))
    expect(original.reload.status).to eq('confirmed')
    expect(BookingClaim.find_by(booking_id: original.id).date).to eq(original.date)
    replacement = track_booking(mutation.change(booking: original, date: '2027-01-04', reason: 'Travel.'))
    expect(replacement.previous_booking).to eq(original)
    expect(original.reload.status).to eq('rescheduled')
  end

  it 'preserves attendance confirmation and cancellation for an existing booking before the new cutoff' do
    program = create_program
    user = create_user
    grant_participant_access(program, user)
    booking = track_booking(attempt(program, user, '2026-11-16'))
    ProgramSettingsUpdate.new(program: program, user: create_user(roles: ['system_admin']))
                         .call(first_bookable_date: '2027-01-01')
    AttendanceMutation.new(program: program, user: user).confirm(booking.id, version: booking.lock_version)
    expect(booking.reload).to be_attendance_confirmed
    expect(booking.date).to eq(Date.new(2026, 11, 16))
    described_class.new(program: program, user: user).cancel(booking: booking, reason: 'Travel.')
    expect(booking.reload.status).to eq('canceled')
    expect(BookingClaim.where(booking_id: booking.id)).to be_empty
    expect(program.bookings.count).to eq(1)
  end

  it 'allows a date change six local calendar days before the saved one-off booking' do
    program = create_program(time_zone: 'America/New_York', start_time: '18:30')
    user = create_user
    grant_participant_access(program, user)
    track_record(
      ProgramScheduleException.create!(
        program: program, date: Date.new(2026, 11, 23), mode: 'open',
        start_time: '20:00', reason: 'Later booking.'
      )
    )
    original = track_booking(attempt(program, user, '2026-11-23'))
    travel_to Time.utc(2026, 11, 18, 4, 59, 59)
    replacement = track_booking(described_class.new(program: program, user: user)
                                               .change(booking: original, date: '2026-11-30', reason: 'Travel.'))
    expect(replacement.date).to eq(Date.new(2026, 11, 30))
    expect(original.reload.status).to eq('rescheduled')
  end

  it 'rechecks the five-day cutoff at program-local midnight after a change page was opened' do
    program = create_program(time_zone: 'America/New_York', start_time: '18:30')
    user = create_user
    grant_participant_access(program, user)
    original = track_booking(attempt(program, user, '2026-11-23'))
    expect(original.rescheduling_locked?).to be(false)
    travel_to Time.utc(2026, 11, 18, 5)
    expect do
      described_class.new(program: program, user: user)
                     .change(booking: original, date: '2026-11-30', reason: 'Travel.')
    end.to raise_error(described_class::Invalid, /contact an organizer/)
    expect(original.reload.status).to eq('confirmed')
    expect(program.bookings.count).to eq(1)
    expect(BookingClaim.find_by(booking_id: original.id).date).to eq(original.date)
  end

  it 'allows only one participant to claim a day and rolls back losing ledger records' do
    program = create_program
    users = Array.new(2) { create_user }
    users.each { |user| grant_participant_access(program, user) }
    results = users.map do |user|
      Thread.new do
        described_class.new(program: program, user: user).book(date: '2026-11-16')
      rescue described_class::Conflict => e
        e
      end
    end.map(&:value)
    track_program_bookings(program)
    expect(results.grep(Booking).size).to eq(1)
    expect(results.grep(described_class::Conflict).map(&:message)).to eq([I18n.t('bookings.date_taken')])
    expect(program.bookings.count).to eq(1)
    expect(BookingClaim.where(program_id: program.id).count).to eq(1)
  end

  it 'allows only one upcoming date per participant even when two dates are claimed concurrently' do
    program = create_program
    user = create_user
    grant_participant_access(program, user)
    results = %w[2026-11-16 2026-11-23].map { |date| Thread.new { attempt(program, user, date) } }.map(&:value)
    track_program_bookings(program)
    expect(results.compact.size).to eq(1)
    expect(program.bookings.count).to eq(1)
    expect(BookingClaim.where(program_id: program.id).count).to eq(1)
  end

  it 'releases expired claims without background jobs or deleting historical bookings' do
    program = create_program
    user = create_user
    grant_participant_access(program, user)
    first = track_booking(attempt(program, user, '2026-11-16'))
    travel_to Time.utc(2026, 11, 17, 15)
    expect(attempt(program, user, '2026-11-23')).to be_nil
    ProgramMembership.find_by(program_id: program.id,
                              user_id: user.id).update!(booking_invited_at: Time.current)
    second = track_booking(attempt(program, user, '2026-11-23'))
    expect(first.reload.display_status).to eq('Completed')
    expect(second.date).to eq(Date.new(2026, 11, 23))
    expect(program.bookings.count).to eq(2)
    expect(BookingClaim.where(program_id: program.id).count).to eq(1)
  end

  it 'completes at the optional end instant and releases its claim without ending the prior day' do
    program = create_program(time_zone: 'America/New_York', start_time: '23:00', end_time: '01:30')
    user = create_user
    grant_participant_access(program, user)
    booking = track_booking(attempt(program, user, '2026-11-16'))
    expect(booking.scheduled_ends_at).to eq(Time.utc(2026, 11, 17, 6, 30))
    travel_to Time.utc(2026, 11, 17, 6, 29)
    expect(booking.reload.display_status).not_to eq('Completed')
    expect(BookingClaim.where(booking_id: booking.id)).to exist
    travel_to Time.utc(2026, 11, 17, 6, 30)
    expect(booking.reload.display_status).to eq('Completed')
    expect(attempt(program, user, '2026-11-23')).to be_nil
    expect(BookingClaim.where(booking_id: booking.id)).not_to exist
  end

  it 'keeps the one-upcoming-booking rule program-local' do
    user = create_user
    programs = Array.new(2) { create_program }
    programs.each do |program|
      grant_participant_access(program, user)
      expect(track_booking(attempt(program, user, '2026-11-16'))).to be_persisted
    end
    expect(Booking.upcoming.where(user_id: user.id).count).to eq(2)
  end

  it 'preserves booking dates and UTC expiry across daylight saving and session time-zone edits' do
    travel_to Time.utc(2026, 10, 30, 15)
    program = create_program(time_zone: 'America/New_York', start_time: '18:30')
    user = create_user
    grant_participant_access(program, user)
    booking = track_booking(attempt(program, user, '2026-11-02'))
    program.update!(time_zone: 'America/Los_Angeles')
    expect(booking.reload).to have_attributes(date: Date.new(2026, 11, 2), time_zone: 'America/New_York',
                                              ends_at: Time.utc(2026, 11, 3, 5))
  end

  it 'protects retained booking history from participant deletion entry points' do
    program = create_program
    user = create_user
    grant_participant_access(program, user)
    booking = track_booking(attempt(program, user, '2026-11-16'))
    booking.destroy
    expect(booking.reload).to be_persisted
    expect { booking.delete }.to raise_error(Booking::HistoryRetained)
    expect { Booking.delete_all }.to raise_error(Booking::HistoryRetained)
    expect(program.bookings.count).to eq(1)
  end
end
