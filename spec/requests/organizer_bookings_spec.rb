# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Organizer bookings', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:model) { create_user }
  let(:organizer) { create_user }

  before do
    grant_model_access(venue, model)
    grant_schedule_access(venue, organizer)
    sign_in(organizer)
  end

  def booking_params(**overrides)
    { booking: { user_id: model.id.to_s, date: '2026-11-16', attendance: 'unconfirmed',
                 reason: 'Agreed with the model.' }.merge(overrides) }
  end

  def reserve
    track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-16'))
  end

  it 'creates a booking for an assigned model without granting unrelated administrator permissions' do
    get new_venue_organizer_booking_path(venue)
    expect(response.body).to include('Schedule a Model', model.name)
    expect(response.parsed_body.at_css('#booking_attendance option[value="confirmed"]').text).to eq('Confirmed')
    post venue_organizer_bookings_path(venue), params: booking_params
    record = track_booking(venue.model_bookings.first)
    expect(record).to have_attributes(user_id: model.id, created_by_id: organizer.id)
    get edit_venue_path(venue)
    expect(response).to have_http_status(:forbidden)
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
  end

  it 'edits and clears attendance after the model cutoff while retaining attributed changes' do
    record = reserve
    get edit_venue_organizer_booking_path(venue, record)
    expect(response.body).to include('Edit Booking', 'Attendance not confirmed')
    patch venue_organizer_booking_path(venue, record), params: booking_params(attendance: 'confirmed')
    expect(record.reload.attendance_confirmed_by_id).to eq(organizer.id)
    follow_redirect!
    expect(response.body).to include('Confirmed on ')
    patch venue_organizer_booking_path(venue, record), params: booking_params
    expect(record.reload.attendance_confirmed?).to be(false)
    expect(record.attendance_changes.pluck('confirmed')).to eq([true, false])
    expect(record.attendance_changes.last).to include('changed_by_id' => organizer.id,
                                                      'reason' => 'Agreed with the model.')
  end

  it 'explains a date claimed after the organizer opened the form without creating a second booking' do
    get new_venue_organizer_booking_path(venue)
    other = create_user
    grant_model_access(venue, other)
    track_booking(BookingMutation.new(venue: venue, user: other).book(date: '2026-11-16'))
    post venue_organizer_bookings_path(venue), params: booking_params
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('someone else just booked that date', 'Please choose another available date.')
    expect(response.parsed_body.at_css('#booking_date')['value']).to eq('2026-11-16')
    expect(venue.model_bookings.count).to eq(1)
  end

  it 'reassigns the model and date after the cutoff with linked history and a single updated claim' do
    record = reserve
    other = create_user
    grant_model_access(venue, other)
    patch venue_organizer_booking_path(venue, record),
          params: booking_params(user_id: other.id.to_s, date: '2026-11-23')
    replacement = track_booking(venue.model_bookings.find_by(previous_booking_id: record.id))
    expect(record.reload).to have_attributes(status: 'rescheduled', user_id: model.id, changed_by_id: organizer.id)
    expect(replacement).to have_attributes(user_id: other.id, attendance_confirmed_at: nil)
    expect(ModelBookingClaim.where(venue_id: venue.id).count).to eq(1)
    expect(ModelBookingClaim.find_by(model_booking_id: replacement.id).user_id).to eq(other.id)
  end

  it 'cancels a booking after the cutoff without removing its ledger or confirmation history' do
    record = reserve
    patch venue_organizer_booking_path(venue, record), params: booking_params(attendance: 'confirmed')
    post cancel_venue_organizer_booking_path(venue, record), params: booking_params(reason: 'Model is ill.')
    expect(record.reload).to have_attributes(status: 'canceled', reason: 'Model is ill.', changed_by_id: organizer.id)
    expect(record.attendance_confirmed?).to be(true)
    expect(ModelBookingClaim.where(model_booking_id: record.id)).to be_empty
  end

  it 'submits the organizer cancellation form successfully with forgery protection enabled' do
    protection = OrganizerBookingsController.allow_forgery_protection
    record = reserve
    OrganizerBookingsController.allow_forgery_protection = true
    get edit_venue_organizer_booking_path(venue, record)
    form = response.parsed_body.at_css('form[action$="/cancel"]')
    post form['action'], params: { authenticity_token: form.at_css('input[name="authenticity_token"]')['value'],
                                   booking: { reason: 'Agreed cancellation.' } }
    expect(response).to redirect_to(venue_path(venue, month: '2026-11'))
    expect(record.reload.status).to eq('canceled')
  ensure
    OrganizerBookingsController.allow_forgery_protection = protection
  end

  it 'rejects missing explanations and invalid attendance while preserving submitted form values' do
    record = reserve
    patch venue_organizer_booking_path(venue, record), params: booking_params(reason: '')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Please tell us what changed')
    patch venue_organizer_booking_path(venue, record), params: booking_params(attendance: 'anything')
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.reload.attendance_changes).to be_empty
    expect(record.status).to eq('confirmed')
  end

  it 'rejects foreign models and venue bookings, including direct submissions from a model' do
    record = reserve
    other = create_user
    post venue_organizer_bookings_path(venue), params: booking_params(user_id: other.id.to_s, date: '2026-11-23')
    expect(response).to have_http_status(:unprocessable_content)
    get edit_venue_organizer_booking_path(create_venue, record)
    expect(response).to have_http_status(:not_found)
    sign_in(model)
    patch venue_organizer_booking_path(venue, record), params: booking_params(attendance: 'confirmed')
    expect(response).to have_http_status(:not_found)
    expect(record.reload.attendance_confirmed?).to be(false)
  end
end
