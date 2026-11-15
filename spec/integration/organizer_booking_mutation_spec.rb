# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OrganizerBookingMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:participant) { create_user }
  let(:organizer) { create_user }
  let(:mutation) { described_class.new(program: program, user: organizer) }
  let(:attributes) do
    { date: '2026-11-16', user_id: participant.id.to_s, attendance: 'confirmed', reason: 'Confirmed by phone.',
      lock_version: 0 }
  end

  before do
    grant_participant_access(program, participant)
    grant_coordinator_access(program, organizer)
  end

  def reserve
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
  end

  it 'respects the first bookable date for replacements while retaining earlier attendance controls' do
    original = reserve
    ProgramSettingsUpdate.new(program: program, user: organizer).call(first_bookable_date: '2027-01-01')
    mutation.update(original.id, attributes)
    expect(original.reload).to be_attendance_confirmed
    expect { mutation.create(attributes.merge(date: '2026-12-28')) }.to raise_error(BookingMutation::Invalid)
    version = original.lock_version
    expect { mutation.update(original.id, attributes.merge(date: '2026-12-28', lock_version: version)) }
      .to raise_error(BookingMutation::Invalid)
    expect(original.reload.status).to eq('confirmed')
    replacement = track_booking(
      mutation.update(original.id, attributes.merge(date: '2027-01-04', lock_version: version))
    )
    expect(replacement.date).to eq(Date.new(2027, 1, 4))
    expect(replacement.previous_booking).to eq(original)
  end

  it 'rolls back a date replacement and its history when the destination is occupied' do
    original = reserve
    other = create_user
    grant_participant_access(program, other)
    track_booking(BookingMutation.new(program: program, user: other).book(date: '2026-11-23'))
    expect do
      mutation.update(original.id, attributes.merge(date: '2026-11-23'))
    end.to raise_error(BookingMutation::Conflict, I18n.t('bookings.date_taken'))
    expect(original.reload.status).to eq('confirmed')
    expect(original.lock_version).to eq(0)
    expect(original.attendance_changes).to be_empty
    expect(program.bookings.count).to eq(2)
    expect(BookingClaim.find_by(booking_id: original.id).date).to eq(original.date)
  end

  it 'can reassign the same date but preserves the one-upcoming-booking constraint for the new participant' do
    original = reserve
    other = create_user
    grant_participant_access(program, other)
    replacement = track_booking(mutation.update(original.id, attributes.merge(user_id: other.id.to_s)))
    expect(original.reload.status).to eq('rescheduled')
    expect(replacement).to have_attributes(date: original.date, user_id: other.id)
    expect do
      mutation.create(attributes.merge(user_id: other.id.to_s, date: '2026-11-23'))
    end.to raise_error(BookingMutation::Conflict)
    expect(program.bookings.count).to eq(2)
  end

  it 'rechecks authorization for loaded organizers and permits system admins without membership' do
    original = reserve
    program.memberships.coordinators.find_by(user_id: organizer.id).revoke_coordinator_access
    expect { mutation.update(original.id, attributes) }.to raise_error(BookingMutation::Invalid, /Schedule access/)
    admin = create_user(roles: ['system_admin'])
    described_class.new(program: program, user: admin).update(original.id, attributes)
    expect(original.reload.attendance_confirmed_by_id).to eq(admin.id)
  end

  it 'rejects invalid new bookings and attendance without leaving claims or booking records' do
    [{ date: 'invalid' }, { attendance: 'anything' }, { user_id: create_user.id.to_s }].each do |changes|
      expect { mutation.create(attributes.merge(changes)) }.to raise_error(BookingMutation::Invalid)
    end
    expect(program.bookings).to be_empty
    expect(BookingClaim.where(program_id: program.id)).to be_empty
  end

  it 'rolls back a retained cancellation if its claim cannot be released' do
    original = reserve
    BookingClaim.where(booking_id: original.id).delete_all
    expect { mutation.cancel(original.id, reason: 'Plans changed.', version: original.lock_version) }
      .to raise_error(BookingMutation::Conflict)
    expect(original.reload.status).to eq('confirmed')
  end
end
