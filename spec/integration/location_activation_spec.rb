# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationActivation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:venue) { program.venue }
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:participant) { create_user }

  def activate(location, value)
    Current.set(user: admin) { described_class.new(location: location, user: admin).call(value) }
  end

  def reserve
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-30'))
  end

  it 'keeps records without stored activation fields public and bookable without a migration' do
    [program, venue].each do |location|
      location.class.collection.find(_id: location.id).update_one('$unset' => { active: '' })
      expect(location.reload).to be_active
      expect(location.class.viewable_by(nil)).to include(location)
    end
    expect(reserve).to be_persisted
  end

  it 'disables every child without overwriting program choices and restores only independently active programs' do
    other = create_program(venue: venue, active: false)
    membership = grant_participant_access(program, participant)
    activate(venue, false)
    expect(program.reload).to be_active
    expect(program).not_to be_booking_active
    expect(BookingAccess.new(membership.reload)).not_to be_allowed
    expect(ParticipantDashboard.new(participant).bookable_programs).to be_empty
    expect(ProgramCalendar.new(program).blocked_reason(Date.new(2026, 11, 30))).to eq('Inactive')
    activate(venue, true)
    expect(program.reload).to be_booking_active
    expect(other.reload).not_to be_booking_active
    expect(BookingAccess.new(membership.reload)).to be_allowed
  end

  it 'rejects stale participant and organizer bookings but retains attendance-only updates' do
    original = reserve
    activate(venue, false)
    mutation = BookingMutation.new(program: program, user: participant)
    expect { mutation.change(booking: original, date: '2026-12-07', reason: 'Travel.') }
      .to raise_error(BookingMutation::Invalid, /inactive/)
    organizer = OrganizerBookingMutation.new(program: program, user: admin)
    attributes = { date: '2026-11-30', user_id: participant.id.to_s, attendance: 'confirmed',
                   reason: 'Confirmed by phone.', lock_version: original.lock_version }
    organizer.update(original.id, attributes)
    expect(original.reload).to be_attendance_confirmed
    expect { organizer.update(original.id, attributes.merge(date: '2026-12-07', lock_version: original.lock_version)) }
      .to raise_error(BookingMutation::Invalid, /inactive/)
    expect { organizer.create(attributes.merge(date: '2026-12-14')) }
      .to raise_error(BookingMutation::Invalid, /inactive/)
    expect(program.bookings.count).to eq(1)
  end

  it 'invalidates old booking forms when a program is disabled and activated again' do
    grant_participant_access(program, participant)
    revision = program.schedule_revision
    activate(program, false)
    activate(program, true)
    expect do
      BookingMutation.new(program: program, user: participant).book(date: '2026-11-30', schedule_revision: revision)
    end.to raise_error(BookingMutation::Stale)
  end

  it 'checks fresh privileges and leaves unrelated invalid legacy settings unchanged' do
    venue.set(address: nil)
    activate(venue, false)
    expect(venue.reload).to have_attributes(active: false, address: nil)
    admin.set(roles: [])
    expect { activate(venue, true) }.to raise_error(described_class::Forbidden)
    expect(venue.reload).not_to be_active
  end

  it 'keeps a booking that commits before concurrent venue deactivation and blocks subsequent bookings' do
    grant_participant_access(program, participant)
    operations = [
      Thread.new do
        track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-30'))
      rescue BookingMutation::Invalid
        nil
      end,
      Thread.new { activate(venue, false) }
    ]
    operations.each(&:value)
    expect(venue.reload).not_to be_active
    expect(program.bookings.count).to be <= 1
    expect(program.bookings.map(&:status)).to all(eq('confirmed'))
    expect { reserve }.to raise_error(BookingMutation::Invalid, /inactive/)
  end
end
