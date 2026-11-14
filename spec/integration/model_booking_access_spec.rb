# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ModelBookingAccess, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:model) { create_user }
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:membership) { grant_model_access(venue, model) }

  def booking(date = '2026-11-16')
    membership
    track_booking(BookingMutation.new(venue: venue, user: model).book(date: date))
  end

  def access_mutation
    ModelAccessMutation.new(venue: venue, user: admin)
  end

  it 'ends permission at completion and requires an explicit new invitation to book again' do
    original = booking
    travel_to Time.utc(2026, 11, 17, 15)
    expect(described_class.new(membership.reload).allowed?).to be(false)
    expect { booking('2026-11-23') }.to raise_error(BookingMutation::Invalid, /organizer/)
    access_mutation.invite(membership.id)
    expect(booking('2026-11-23')).to be_persisted
    expect(original.reload.display_status).to eq('Completed')
    expect(venue.model_bookings.count).to eq(2)
  end

  it 'retains permission across cancellation even after the canceled date has passed' do
    original = booking
    BookingMutation.new(venue: venue, user: model).cancel(booking: original, reason: 'Travel.')
    travel_to Time.utc(2026, 11, 17, 15)
    expect(booking('2026-11-23')).to be_persisted
    expect(original.reload.status).to eq('canceled')
  end

  it 'keeps a paused booking while preventing rescheduling but still allows cancellation' do
    original = booking
    Current.set(user: admin) { access_mutation.pause(membership.id, 'Needs a break.') }
    expect(original.reload.status).to eq('confirmed')
    mutation = BookingMutation.new(venue: venue, user: model)
    expect { mutation.change(booking: original, date: '2026-11-23', reason: 'Travel.') }
      .to raise_error(BookingMutation::Invalid, /paused/)
    mutation.cancel(booking: original, reason: 'Cannot attend.')
    expect { booking('2026-11-23') }.to raise_error(BookingMutation::Invalid, /paused/)
    expect(membership.reload.history_tracks.last).to have_attributes(modifier_id: admin.id)
  end

  it 'resumes without creating another entitlement after a completed drawing' do
    booking
    access_mutation.pause(membership.id, 'Pause until ready.')
    travel_to Time.utc(2026, 11, 17, 15)
    access_mutation.resume(membership.id)
    expect(membership.reload.model_pause_reason).to eq('Pause until ready.')
    expect(described_class.new(membership).allowed?).to be(false)
    expect(access_mutation.invite(membership.id)).to be_present
    expect(described_class.new(membership.reload).allowed?).to be(true)
  end

  it 'does not let a fresh registration invitation bypass a paused or completed model gate' do
    booking
    travel_to Time.utc(2026, 11, 17, 15)
    ModelInvitation.with_session { |session| VenueMembership.grant_model_access(venue, model, session: session) }
    expect(described_class.new(membership.reload).allowed?).to be(false)
    access_mutation.pause(membership.id, 'Organizer hold.')
    expect(access_mutation.invite(membership.id)).to be_nil
  end

  it 'preserves existing legacy reservations and cancellation rights without granting another completed cycle' do
    original = booking
    membership.unset(:booking_invited_at)
    expect(described_class.new(membership.reload).allowed?).to be(true)
    BookingMutation.new(venue: venue, user: model).cancel(booking: original, reason: 'Travel.')
    travel_to Time.utc(2026, 11, 17, 15)
    replacement = booking('2026-11-23')
    travel_to Time.utc(2026, 11, 24, 15)
    expect(replacement.reload.display_status).to eq('Completed')
    expect(described_class.new(membership.reload).allowed?).to be(false)
  end

  it 'retains a valid grant through pause/resume and requires a short pause explanation' do
    membership
    expect { access_mutation.pause(membership.id, ' ') }.to raise_error(BookingMutation::Invalid)
    access_mutation.pause(membership.id, 'Temporary hold.')
    access_mutation.resume(membership.id)
    expect(booking).to be_persisted
    expect(membership.reload.history_tracks.count).to eq(3)
  end

  it 'isolates completed-cycle permission and pauses to their venue' do
    booking
    other = create_venue
    other_membership = grant_model_access(other, model)
    travel_to Time.utc(2026, 11, 17, 15)
    ModelAccessMutation.new(venue: other, user: admin).invite(other_membership.id)
    access_mutation.pause(membership.id, 'Venue-local pause.')
    expect(described_class.new(membership.reload).allowed?).to be(false)
    expect(described_class.new(other_membership.reload).allowed?).to be(true)
  end

  it 'serializes a pause with a booking without deleting a reservation that won the race' do
    membership
    operations = [
      Thread.new do
        booking
      rescue BookingMutation::Invalid
        nil
      end,
      Thread.new { access_mutation.pause(membership.id, 'Organizer pause.') }
    ]
    operations.each(&:value)
    expect(membership.reload.model_paused).to be(true)
    expect(venue.model_bookings.count).to be <= 1
    expect { booking('2026-11-23') }.to raise_error(BookingMutation::Invalid, /paused/)
  end
end
