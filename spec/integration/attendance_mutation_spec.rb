# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AttendanceMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:participant) { create_user }
  let(:booking) do
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-23'))
  end

  def confirm
    described_class.new(program: program, user: participant).confirm(booking.id,
                                                                     version: booking.lock_version)
  end

  def allow_stale
    yield
  rescue BookingMutation::Stale
    nil
  end

  it 'uses saved local calendar dates across daylight saving and later session time-zone changes' do
    travel_to Time.utc(2026, 10, 24, 15)
    grant_participant_access(program, participant)
    record = track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-02'))
    program.update!(time_zone: 'America/Los_Angeles')
    travel_to Time.utc(2026, 10, 26, 3, 59, 59)
    expect(record.confirmation_open?).to be(false)
    travel_to Time.utc(2026, 10, 26, 4)
    expect(record.confirmation_open?).to be(true)
    travel_to Time.utc(2026, 10, 28, 4)
    expect(record.rescheduling_locked?).to be(true)
    expect(record.scheduled_start).to eq(Time.utc(2026, 11, 2, 23, 30))
  end

  it 'closes confirmation at the drawing start but retains a previous confirmation' do
    record = booking
    travel_to record.scheduled_start
    expect { confirm }.to raise_error(BookingMutation::Invalid, /closes when it starts/)
    expect(record.reload.attendance_confirmed?).to be(false)
  end

  it 'retains prior confirmation metadata without marking the old date or its replacement confirmed' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    confirm
    replacement = track_booking(BookingMutation.new(program: program, user: participant)
                                               .change(booking: record.reload, date: '2026-11-30', reason: 'Travel.'))
    expect(record.reload.attendance_confirmed?).to be(false)
    expect(record.attendance_confirmed_at).to be_present
    expect(record.attendance_changes.last['changed_by_id']).to eq(participant.id)
    expect(replacement.attendance_confirmed?).to be(false)
  end

  it 'rechecks membership and account activity inside the transaction even for loaded users' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    User.find(participant.id).update!(active: false)
    expect { confirm }.to raise_error(BookingMutation::Invalid, /model invitation/)
    expect(record.reload.attendance_confirmed?).to be(false)
  end

  it 'serializes competing confirmations without duplicating attendance history' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    2.times.map { Thread.new { confirm } }.each(&:value)
    expect(record.reload.attendance_changes.size).to eq(1)
  end

  it 'does not replay an old confirmation over an organizer deliberately clearing attendance' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    confirm
    organizer = create_user
    grant_coordinator_access(program, organizer)
    OrganizerBookingMutation.new(program: program, user: organizer).update(
      record.id, date: record.date.iso8601, user_id: participant.id.to_s, attendance: 'unconfirmed',
                 reason: 'Rechecking availability.', lock_version: record.reload.lock_version
    )
    expect { described_class.new(program: program, user: participant).confirm(record.id, version: 0) }
      .to raise_error(BookingMutation::Stale)
    expect(record.reload.attendance_confirmed?).to be(false)
    expect(record.attendance_changes.size).to eq(2)
  end

  it 'serializes confirmation with a reschedule without confirming the replacement accidentally' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    confirming = Thread.new { allow_stale { confirm } }
    replacement = allow_stale do
      BookingMutation.new(program: program, user: participant).change(booking: record, date: '2026-11-30',
                                                                      reason: 'Travel.')
    end
    track_booking(replacement) if replacement
    confirming.value
    expect(record.reload.status).to eq(replacement ? 'rescheduled' : 'confirmed')
    expect(replacement.attendance_confirmed?).to be(false) if replacement
    expect(record.attendance_changes.size).to be <= 1
  end
end
