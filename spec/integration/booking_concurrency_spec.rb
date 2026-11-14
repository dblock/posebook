# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Booking, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:participant) { create_user }
  let(:organizer) { create_user }
  let(:booking) do
    grant_participant_access(program, participant)
    grant_coordinator_access(program, organizer)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-23'))
  end

  def race(*operations)
    operations.map do |operation|
      Thread.new do
        operation.call
      rescue BookingMutation::Stale => e
        e
      end
    end.map(&:value)
  end

  def organizer_mutation
    OrganizerBookingMutation.new(program: program, user: organizer)
  end

  it 'atomically rejects stale writes even on legacy bookings without a stored revision' do
    described_class.collection.find(_id: booking.id).update_one('$unset' => { lock_version: '' })
    first, stale = Array.new(2) { described_class.find(booking.id) }
    Program.with_session do |session|
      first.record_attendance!(true, organizer, 'Confirmed by phone.', session: session)
      expect { stale.close!('canceled', 'Stale cancellation.', participant, session: session) }
        .to raise_error(BookingMutation::Stale)
    end
    expect(booking.reload).to have_attributes(lock_version: 1, status: 'confirmed')
    expect(booking.attendance_changes.size).to eq(1)
    expect(booking.reason).to be_nil
  end

  it 'lets only one of two simultaneous reschedules replace the same original booking' do
    snapshots = Array.new(2) { described_class.find(booking.id) }
    operations = snapshots.zip(%w[2026-11-30 2026-12-07]).map do |snapshot, date|
      lambda {
        BookingMutation.new(program: program, user: participant).change(booking: snapshot, date: date,
                                                                        reason: 'Travel.')
      }
    end
    results = race(*operations)
    program.bookings.each { |record| track_booking(record) }
    expect(results.grep(described_class).size).to eq(1)
    expect(results.grep(BookingMutation::Stale).size).to eq(1)
    expect(booking.reload).to have_attributes(status: 'rescheduled', lock_version: 1)
    expect(program.bookings.count).to eq(2)
    expect(BookingClaim.where(program_id: program.id).count).to eq(1)
  end

  it 'does not let a competing cancellation overwrite an attendance edit or vice versa' do
    version = booking.lock_version
    attributes = { date: booking.date.iso8601, user_id: participant.id.to_s, attendance: 'confirmed',
                   reason: 'Confirmed by phone.', lock_version: version }
    results = race(-> { organizer_mutation.update(booking.id, attributes) },
                   -> { organizer_mutation.cancel(booking.id, reason: 'Canceled by phone.', version: version) })
    expect(results.grep(described_class).size).to eq(1)
    expect(results.grep(BookingMutation::Stale).size).to eq(1)
    expect(booking.reload.lock_version).to eq(1)
    expect(booking.attendance_changes.size).to eq(booking.status == 'confirmed' ? 1 : 0)
    expect(BookingClaim.where(booking_id: booking.id).count).to eq(booking.status == 'confirmed' ? 1 : 0)
  end

  it 'invalidates an old participant snapshot when an organizer changes the drawing time' do
    snapshot = described_class.find(booking.id)
    track_record(ProgramScheduleMutation.new(program: program, user: organizer).call(
                   date: booking.date.iso8601, mode: 'open', start_time: '20:00', reason: 'Later drawing.'
                 ))
    expect do
      BookingMutation.new(program: program, user: participant).change(booking: snapshot, date: '2026-11-30',
                                                                      reason: 'Travel.')
    end.to raise_error(BookingMutation::Stale)
    expect(booking.reload.lock_version).to eq(1)
    expect(booking.time_changes.size).to eq(1)
    expect(program.bookings.count).to eq(1)
    expect(BookingClaim.find_by(booking_id: booking.id).date).to eq(booking.date)
  end
end
