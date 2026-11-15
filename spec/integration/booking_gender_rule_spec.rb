# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingGenderRule, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(no_consecutive_genders: ['male']) }
  let(:participant) { create_user(gender: 'male') }

  before { grant_participant_access(program, participant) }

  def reserve(date, gender: 'male', at: program)
    user = create_user(gender: gender)
    grant_participant_access(at, user)
    track_booking(BookingMutation.new(program: at, user: user).book(date: date))
  end

  def book(date)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: date))
  end

  def change(original, date)
    track_booking(BookingMutation.new(program: program, user: participant)
                                .change(booking: original, date: date, reason: 'Travel changed.'))
  end

  def exception(date, mode)
    track_record(
      ProgramScheduleException.create!(program: program, date: Date.iso8601(date), mode: mode,
                                       start_time: mode == 'open' ? '18:30' : nil, reason: 'Schedule change.')
    )
  end

  def attempt(user, date)
    BookingMutation.new(program: program, user: user).book(date: date)
  rescue BookingMutation::Invalid
    nil
  end

  User::GENDERS.each do |gender|
    it "independently restricts consecutive #{gender} participants when that gender is selected" do
      program.update!(no_consecutive_genders: [gender])
      participant.update!(gender: gender)
      reserve('2026-11-16', gender: gender)
      decision = described_class.new(program).evaluate(Date.new(2026, 11, 23), participant)
      expect(decision).to have_attributes(code: :gender_restricted, overridable: true)
      expect(decision.message).to include('consecutive-gender rule')
      expect { book('2026-11-23') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
      expect(program.bookings.count).to eq(1)
      program.update!(no_consecutive_genders: [])
      expect(book('2026-11-23')).to be_persisted
    end
  end

  it 'allows consecutive female participants when only male repeats are restricted' do
    reserve('2026-11-16', gender: 'female')
    participant.update!(gender: 'female')
    expect(book('2026-11-23')).to be_persisted
  end

  it 'checks the next scheduled session too, including across month boundaries' do
    reserve('2026-12-07')
    expect { book('2026-11-30') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
  end

  it 'does not skip an unbooked session when looking for the preceding participant' do
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

  it 'checks completed bookings and their historical one-off schedule' do
    travel_to Time.utc(2026, 11, 6, 15)
    exception('2026-11-12', 'open')
    previous = reserve('2026-11-12')
    travel_to Time.utc(2026, 11, 13, 15)
    expect(previous.display_status).to eq('Completed')
    expect { book('2026-11-16') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
  end

  it 'ignores canceled bookings and bookings at other sessions' do
    previous = reserve('2026-11-16')
    BookingMutation.new(program: program, user: previous.user).cancel(booking: previous,
                                                                      reason: 'Travel changed.')
    reserve('2026-11-16', at: create_program)
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
    expect(BookingClaim.find_by(booking_id: original.id).date).to eq(original.date)
    expect(program.bookings.count).to eq(2)
  end

  it 'allows booking and rescheduling without a gender when no rules are enabled' do
    program.update!(no_consecutive_genders: [])
    participant.set(gender: nil)
    expect(described_class.new(program).evaluate(Date.new(2026, 11, 23), participant)).to be_nil
    original = book('2026-11-23')
    replacement = change(original, '2026-11-30')
    expect(replacement).to be_persisted
    expect(replacement.starts_at).to eq(Time.utc(2026, 11, 30, 9))
    expect(original.reload.status).to eq('rescheduled')
  end

  it 'reports a missing-gender decision that organizers cannot override using configured labels' do
    program.update!(program_label: 'Workshop', participant_label: 'Instructor')
    participant.set(gender: nil)
    decision = described_class.new(program).evaluate(Date.new(2026, 11, 23), participant)
    expect(decision).to be_a(BookingRuleDecision)
    expect(decision).to have_attributes(
      code: :gender_required, overridable: false,
      message: "Select a gender in the instructor's profile to book with this workshop's gender rules."
    )
    expect(ProgramCalendar.new(program).gender_blocked_reason(Date.new(2026, 11, 23), participant))
      .to eq('Select gender')
  end

  it 'requires a gender after enabling rules without changing an existing booking' do
    program.update!(no_consecutive_genders: [])
    participant.set(gender: nil)
    original = book('2026-11-23')
    program.update!(no_consecutive_genders: ['male'])
    expect { change(original, '2026-11-30') }.to raise_error(BookingMutation::Invalid, /Select a gender/)
    expect(original.reload.status).to eq('confirmed')
    expect(BookingClaim.find_by(booking_id: original.id).date).to eq(original.date)
  end

  it 'reloads the selected gender rather than trusting a stale profile' do
    reserve('2026-11-16')
    participant.update!(gender: 'female')
    User.find(participant.id).update!(gender: 'male')
    expect { book('2026-11-23') }.to raise_error(BookingMutation::Invalid, /consecutive-gender/)
  end

  it 'serializes competing adjacent bookings so only one restricted participant succeeds' do
    other = create_user(gender: 'male')
    grant_participant_access(program, other)
    results = [participant, other].zip(%w[2026-11-16 2026-11-23])
                                  .map { |user, date| Thread.new { attempt(user, date) } }.map(&:value)
    program.bookings.each { |booking| track_booking(booking) }
    expect(results.compact.size).to eq(1)
    expect(program.bookings.count).to eq(1)
    expect(BookingClaim.where(program_id: program.id).count).to eq(1)
  end
end
