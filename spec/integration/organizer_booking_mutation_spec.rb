# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OrganizerBookingMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:model) { create_user }
  let(:organizer) { create_user }
  let(:mutation) { described_class.new(venue: venue, user: organizer) }
  let(:attributes) do
    { date: '2026-11-16', user_id: model.id.to_s, attendance: 'confirmed', reason: 'Confirmed by phone.',
      lock_version: 0 }
  end

  before do
    grant_model_access(venue, model)
    grant_schedule_access(venue, organizer)
  end

  def reserve
    track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-16'))
  end

  it 'rolls back a date replacement and its history when the destination is occupied' do
    original = reserve
    other = create_user
    grant_model_access(venue, other)
    track_booking(BookingMutation.new(venue: venue, user: other).book(date: '2026-11-23'))
    expect do
      mutation.update(original.id, attributes.merge(date: '2026-11-23'))
    end.to raise_error(BookingMutation::Conflict, I18n.t('bookings.date_taken'))
    expect(original.reload.status).to eq('confirmed')
    expect(original.lock_version).to eq(0)
    expect(original.attendance_changes).to be_empty
    expect(venue.model_bookings.count).to eq(2)
    expect(ModelBookingClaim.find_by(model_booking_id: original.id).date).to eq(original.date)
  end

  it 'can reassign the same date but preserves the one-upcoming-booking constraint for the new model' do
    original = reserve
    other = create_user
    grant_model_access(venue, other)
    replacement = track_booking(mutation.update(original.id, attributes.merge(user_id: other.id.to_s)))
    expect(original.reload.status).to eq('rescheduled')
    expect(replacement).to have_attributes(date: original.date, user_id: other.id)
    expect do
      mutation.create(attributes.merge(user_id: other.id.to_s, date: '2026-11-23'))
    end.to raise_error(BookingMutation::Conflict)
    expect(venue.model_bookings.count).to eq(2)
  end

  it 'rechecks authorization for loaded organizers and permits system admins without membership' do
    original = reserve
    venue.memberships.schedule_managers.find_by(user_id: organizer.id).revoke_schedule_access
    expect { mutation.update(original.id, attributes) }.to raise_error(BookingMutation::Invalid, /Schedule access/)
    admin = create_user(roles: ['system_admin'])
    described_class.new(venue: venue, user: admin).update(original.id, attributes)
    expect(original.reload.attendance_confirmed_by_id).to eq(admin.id)
  end

  it 'rejects invalid new bookings and attendance without leaving claims or booking records' do
    [{ date: 'invalid' }, { attendance: 'anything' }, { user_id: create_user.id.to_s }].each do |changes|
      expect { mutation.create(attributes.merge(changes)) }.to raise_error(BookingMutation::Invalid)
    end
    expect(venue.model_bookings).to be_empty
    expect(ModelBookingClaim.where(venue_id: venue.id)).to be_empty
  end

  it 'rolls back a retained cancellation if its claim cannot be released' do
    original = reserve
    ModelBookingClaim.where(model_booking_id: original.id).delete_all
    expect { mutation.cancel(original.id, reason: 'Plans changed.', version: original.lock_version) }
      .to raise_error(BookingMutation::Conflict)
    expect(original.reload.status).to eq('confirmed')
  end
end
