# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Model bookings', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:model) { create_user }

  def prepare_model
    grant_model_access(venue, model)
    sign_in(model)
  end

  def book(date = '2026-11-16', user: model, at: venue)
    track_booking(BookingMutation.new(venue: at, user: user).book(date: date))
  end

  it 'requires authentication, venue access, and a model membership before booking' do
    create_user
    post venue_model_bookings_path(venue), params: { date: '2026-11-16' }
    expect(response).to redirect_to(new_session_path)
    sign_in(model)
    post venue_model_bookings_path(venue), params: { date: '2026-11-16' }
    expect(response).to have_http_status(:not_found)
    grant_schedule_access(venue, model)
    post venue_model_bookings_path(venue), params: { date: '2026-11-16' }
    expect(response).to have_http_status(:forbidden)
    expect(venue.model_bookings).to be_empty
  end

  it 'books an available date and blocks further bookings while offering change and cancel' do
    prepare_model
    post venue_model_bookings_path(venue), params: { date: '2026-11-16', user_id: create_user.id }
    booking = track_booking(venue.model_bookings.first)
    expect(booking.user_id).to eq(model.id)
    follow_redirect!
    expect(response.body).to include('Your posing date is booked.', 'Your Upcoming Booking', 'Change Date',
                                     'Cancel Booking')
    expect(response.parsed_body.css('.calendar form')).to be_empty
    post venue_model_bookings_path(venue), params: { date: '2026-11-23' }
    follow_redirect!
    expect(response.body).to include('You already have an upcoming booking')
    expect(venue.model_bookings.count).to eq(1)
  end

  it 'rejects malformed, past, non-posing, and out-of-horizon dates on the server' do
    prepare_model
    ['invalid', '2026-11-09', '2026-11-17', '2027-05-17', nil].each do |date|
      post venue_model_bookings_path(venue), params: { date: date }
      follow_redirect!
      expect(response.body).to include('Choose an available date')
      expect(venue.model_bookings).to be_empty
    end
  end

  it 'reschedules with an explanation while preserving and linking both records' do
    prepare_model
    original = book
    get edit_venue_model_booking_path(venue, original)
    expect(response.body).to include('Change Your Posing Date', 'booking-change-form')
    patch venue_model_booking_path(venue, original), params: { date: '2026-11-23', reason: 'Travel plans changed.' }
    replacement = track_booking(venue.model_bookings.where(previous_booking_id: original.id).first)
    expect(original.reload).to have_attributes(date: Date.new(2026, 11, 16), status: 'rescheduled',
                                               reason: 'Travel plans changed.', changed_by_id: model.id)
    expect(replacement.date).to eq(Date.new(2026, 11, 23))
    follow_redirect!
    expect(response.body).to include('Rescheduled', 'Moved from 2026-11-16', 'Travel plans changed.', 'Confirmed')
  end

  it 'keeps the original booking if a requested replacement date is occupied' do
    prepare_model
    original = book
    other = create_user
    grant_model_access(venue, other)
    book('2026-11-23', user: other)
    patch venue_model_booking_path(venue, original), params: { date: '2026-11-23', reason: 'Need another date.' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('just changed')
    expect(original.reload.status).to eq('confirmed')
    expect(venue.model_bookings.count).to eq(2)
    expect(ModelBookingClaim.find_by(user_id: model.id).model_booking_id).to eq(original.id)
  end

  it 'requires explanations and keeps month navigation on the change form after errors' do
    prepare_model
    original = book
    patch venue_model_booking_path(venue, original), params: { date: '2026-11-23', reason: ' ' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Provide an explanation')
    expect(response.parsed_body.at_css('nav[aria-label="Calendar months"] a')['href'])
      .to start_with(edit_venue_model_booking_path(venue, original))
    post cancel_venue_model_booking_path(venue, original), params: { reason: '' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(original.reload.status).to eq('confirmed')
  end

  it 'retains a canceled booking and explanation when the model books a different day' do
    prepare_model
    original = book
    get cancellation_venue_model_booking_path(venue, original)
    expect(response.body).to include('Cancel Your Booking')
    post cancel_venue_model_booking_path(venue, original), params: { reason: 'A family commitment.' }
    expect(original.reload).to have_attributes(status: 'canceled', reason: 'A family commitment.')
    post venue_model_bookings_path(venue), params: { date: '2026-11-23' }
    replacement = track_booking(venue.model_bookings.where(status: 'confirmed').first)
    expect(replacement.id).not_to eq(original.id)
    follow_redirect!
    expect(response.body).to include('2026-11-16', 'Canceled', 'A family commitment.', '2026-11-23', 'Confirmed')
    post cancel_venue_model_booking_path(venue, original), params: { reason: 'Overwrite history' }
    expect(response).to have_http_status(:not_found)
    expect(original.reload.reason).to eq('A family commitment.')
  end

  it 'never exposes another model history or permits changing another user or venue booking' do
    prepare_model
    original = book
    other = create_user(name: 'Another Model')
    grant_model_access(venue, other)
    sign_in(other)
    get venue_path(venue)
    expect(response.body).not_to include(model.email, model.name, 'Change Date')
    get edit_venue_model_booking_path(venue, original)
    expect(response).to have_http_status(:not_found)
    post cancel_venue_model_booking_path(venue, original), params: { reason: 'Forbidden' }
    expect(response).to have_http_status(:not_found)
    expect(original.reload.status).to eq('confirmed')
  end

  it 'lets scoped organizers see venue history without granting model booking privileges' do
    prepare_model
    original = book
    organizer = create_user(name: 'Venue Organizer')
    grant_schedule_access(venue, organizer)
    sign_in(organizer)
    get venue_path(venue)
    expect(response.body).to include('Venue Booking History', model.name, original.date.iso8601)
    expect(response.parsed_body.css('.calendar form')).to be_empty
    get venue_path(create_venue)
    expect(response).to have_http_status(:not_found)
  end

  it 'honors existing reservations after venue weekdays or horizon settings change' do
    prepare_model
    original = book
    venue.update!(available_weekdays: ['2'])
    get venue_path(venue)
    expect(response.body).to include('Your Upcoming Booking', 'Change Date', 'Cancel Booking')
    expect(original.reload.status).to eq('confirmed')
    patch venue_model_booking_path(venue, original), params: { date: '2026-11-17', reason: 'New venue weekday.' }
    replacement = track_booking(venue.model_bookings.where(previous_booking_id: original.id).first)
    expect(replacement.date).to eq(Date.new(2026, 11, 17))
  end
end
