# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProgramScheduleMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(time_zone: 'America/New_York', start_time: '18:30') }
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:participant) { create_user }

  def change_schedule(**attributes)
    values = { date: '2026-11-16', mode: 'open', start_time: '19:30', reason: 'Later booking.' }.merge(attributes)
    track_record(described_class.new(program: program, user: admin).call(values))
  end

  def reserve(date = '2026-11-16')
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: date))
  end

  it 'opens an extra weekday at its specified local time without changing other dates' do
    change_schedule(date: '2026-11-17', start_time: '14:00')
    calendar = ProgramCalendar.new(program)
    expect(calendar.blocked_reason(Date.new(2026, 11, 17))).to be_nil
    expect(calendar.blocked_reason(Date.new(2026, 11, 24))).to eq('Not a scheduled day')
    expect(reserve('2026-11-17').starts_at).to eq(Time.utc(2026, 11, 17, 19))
  end

  it 'closes an occupied regular date with its explanation and frees only the disposable claim' do
    booking = reserve
    change_schedule(mode: 'closed', reason: 'Thanksgiving holiday.')
    expect(booking.reload).to have_attributes(status: 'canceled', reason: 'Thanksgiving holiday.',
                                              changed_by_id: admin.id, date: Date.new(2026, 11, 16))
    expect(BookingClaim.where(booking_id: booking.id)).to be_empty
    expect(program.bookings.count).to eq(1)
    expect(
      ProgramCalendar.new(program).blocked_reason(booking.date)
    ).to eq('Closed: Thanksgiving holiday.')
  end

  it 'changes one booked time while retaining the same booking and an attributed time-change ledger' do
    booking = reserve
    change_schedule
    expect(booking.reload).to have_attributes(status: 'confirmed', starts_at: Time.utc(2026, 11, 17, 0, 30))
    expect(booking.time_changes.last).to include('from' => Time.utc(2026, 11, 16, 23, 30),
                                                 'to' => Time.utc(2026, 11, 17, 0, 30),
                                                 'reason' => 'Later booking.', 'changed_by_id' => admin.id)
    expect(BookingClaim.find_by(booking_id: booking.id).user_id).to eq(participant.id)
    expect(program.bookings.count).to eq(1)
  end

  it 'restores regular scheduling without deleting the prior exception or its history' do
    first = change_schedule(mode: 'closed', reason: 'Holiday.')
    Current.set(user: admin) { change_schedule(mode: 'regular', reason: 'Program reopened.') }
    expect(first.reload.mode).to eq('regular')
    expect(first.history_tracks.count).to eq(2)
    expect(first.history_tracks.last).to have_attributes(modifier_id: admin.id)
    expect(first.history_tracks.last.original['reason']).to eq('Holiday.')
    expect(ProgramCalendar.new(program).blocked_reason(first.date)).to be_nil
  end

  it 'cancels a one-off booking when restoring a normally unavailable weekday' do
    change_schedule(date: '2026-11-17')
    booking = reserve('2026-11-17')
    change_schedule(date: '2026-11-17', mode: 'regular', reason: 'Extra session withdrawn.')
    expect(booking.reload).to have_attributes(status: 'canceled', reason: 'Extra session withdrawn.')
  end

  it 'rejects invalid exceptions without changing the existing booked time' do
    booking = reserve
    [{ reason: ' ' }, { start_time: '25:30' }, { mode: 'invalid' }, { reason: 'x' * 201 },
     { date: '2026-11-09' }, { date: '2027-05-17' }].each do |attributes|
      expect(change_schedule(**attributes).errors).not_to be_empty
    end
    expect(program.schedule_exceptions).to be_empty
    expect(booking.reload.starts_at).to eq(Time.utc(2026, 11, 16, 23, 30))
  end

  it 'rolls back closure, booking cancellation, and audit history if claim removal fails' do
    booking = reserve
    collection = BookingClaim.collection
    view = collection.find(booking_id: booking.id)
    allow(BookingClaim).to receive(:collection).and_return(collection)
    allow(collection).to receive(:find).and_call_original
    allow(collection).to receive(:find).with(booking_id: booking.id).and_return(view)
    allow(view).to receive(:delete_one).and_raise(Mongo::Error::OperationFailure, 'Claim removal failed')
    expect { change_schedule(mode: 'closed') }.to raise_error(Mongo::Error::OperationFailure)
    expect(booking.reload.status).to eq('confirmed')
    expect(program.schedule_exceptions).to be_empty
    expect(HistoryTracker.where('modified.program_id' => program.id)).to be_empty
    expect(BookingClaim.where(booking_id: booking.id).count).to eq(1)
  end

  it 'serializes a holiday closure with a simultaneous booking request' do
    grant_participant_access(program, participant)
    operations = [
      Thread.new do
        track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
      rescue BookingMutation::Invalid
        nil
      end,
      Thread.new { change_schedule(mode: 'closed', reason: 'Holiday.') }
    ]
    operations.each(&:value)
    expect(program.bookings.where(status: 'confirmed')).to be_empty
    expect(BookingClaim.where(program_id: program.id)).to be_empty
  end

  it 'honors daylight saving transitions and rejects nonexistent local start times' do
    change_schedule(date: '2027-03-07', start_time: '18:30')
    change_schedule(date: '2027-03-14', start_time: '18:30')
    schedule = ProgramSchedule.new(program)
    expect(schedule.starts_at(Date.new(2027, 3, 7))).to eq(Time.utc(2027, 3, 7, 23, 30))
    expect(schedule.starts_at(Date.new(2027, 3, 14))).to eq(Time.utc(2027, 3, 14, 22, 30))
    invalid = change_schedule(date: '2027-03-14', start_time: '02:30')
    expect(invalid.errors[:start_time]).not_to be_empty
    expect(program.schedule_exceptions.find_by(date: Date.new(2027, 3, 14)).start_time).to eq('18:30')
  end

  it 'serializes a time override with a simultaneous booking at the effective new time' do
    grant_participant_access(program, participant)
    operations = [
      Thread.new do
        track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
      end,
      Thread.new { change_schedule }
    ]
    operations.each(&:value)
    booking = program.bookings.find_by(status: 'confirmed')
    expect(booking.starts_at).to eq(Time.utc(2026, 11, 17, 0, 30))
    expect(BookingClaim.where(booking_id: booking.id).count).to eq(1)
  end

  it 'rolls back a regular-time change that would move an existing booking into a daylight saving gap' do
    program.update!(available_weekdays: ['0'])
    booking = reserve('2027-03-14')
    result = ProgramSettingsUpdate.new(program: program, user: admin).call(start_time: '02:30')
    expect(result.errors[:start_time]).not_to be_empty
    expect(program.reload.start_time).to eq('18:30')
    expect(booking.reload.starts_at).to eq(Time.utc(2027, 3, 14, 22, 30))
    expect(booking.time_changes).to be_empty
  end

  it 'moves regular future bookings with the default time but leaves dated overrides unchanged' do
    regular = reserve
    change_schedule(date: '2026-11-23', start_time: '20:00')
    other = create_user
    grant_participant_access(program, other)
    overridden = track_booking(BookingMutation.new(program: program,
                                                   user: other).book(date: '2026-11-23'))
    ProgramSettingsUpdate.new(program: program, user: admin).call(start_time: '19:00')
    expect(regular.reload.starts_at).to eq(Time.utc(2026, 11, 17, 0))
    expect(regular.time_changes.last['reason']).to eq('Regular start time changed.')
    expect(overridden.reload.starts_at).to eq(Time.utc(2026, 11, 24, 1))
    expect(overridden.time_changes).to be_empty
  end

  it 'updates an upcoming booking and its claim when an overnight end time changes or is cleared' do
    booking = reserve
    result = ProgramSettingsUpdate.new(program: program, user: admin).call(end_time: '01:15')
    expect(result.errors).to be_empty
    expect(booking.reload).to have_attributes(scheduled_ends_at: Time.utc(2026, 11, 17, 6, 15),
                                              ends_at: Time.utc(2026, 11, 17, 6, 15), lock_version: 1)
    expect(BookingClaim.find_by(booking_id: booking.id).ends_at).to eq(booking.ends_at)
    expect(booking.time_changes.last).to include('from_end' => nil, 'to_end' => booking.ends_at)
    ProgramSettingsUpdate.new(program: program, user: admin).call(end_time: '')
    expect(booking.reload.scheduled_ends_at).to be_nil
    expect(booking.ends_at).to eq(Time.utc(2026, 11, 17, 5))
    expect(BookingClaim.find_by(booking_id: booking.id).ends_at).to eq(booking.ends_at)
  end

  it 'uses per-date end times, preserves them across regular edits, and restores regular times' do
    program.update!(end_time: '21:00')
    booking = reserve
    change_schedule(start_time: '22:30', end_time: '01:00')
    expect(booking.reload).to have_attributes(starts_at: Time.utc(2026, 11, 17, 3, 30),
                                              ends_at: Time.utc(2026, 11, 17, 6))
    ProgramSettingsUpdate.new(program: program, user: admin).call(end_time: '22:00')
    expect(booking.reload.ends_at).to eq(Time.utc(2026, 11, 17, 6))
    change_schedule(mode: 'regular')
    expect(booking.reload.ends_at).to eq(Time.utc(2026, 11, 17, 3))
    expect(BookingClaim.find_by(booking_id: booking.id).ends_at).to eq(booking.ends_at)
  end

  it 'rejects equal and nonexistent end times and rolls back changes to booked dates' do
    booking = reserve
    expect(change_schedule(start_time: '19:30', end_time: '19:30').errors[:end_time]).not_to be_empty
    invalid = change_schedule(date: '2027-03-13', start_time: '23:00', end_time: '02:30')
    expect(invalid.errors[:end_time]).not_to be_empty
    expect(booking.reload.scheduled_ends_at).to be_nil
    expect(program.schedule_exceptions).to be_empty

    program.update!(available_weekdays: ['0'], start_time: '01:00')
    other = create_user
    grant_participant_access(program, other)
    spring_booking = track_booking(BookingMutation.new(program: program, user: other).book(date: '2027-03-14'))
    result = ProgramSettingsUpdate.new(program: program, user: admin).call(end_time: '02:30')
    expect(result.errors[:end_time]).not_to be_empty
    expect(program.reload.end_time).to be_nil
    expect(spring_booking.reload.scheduled_ends_at).to be_nil
  end
end
