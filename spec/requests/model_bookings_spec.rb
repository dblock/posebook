# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Model bookings', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:drawing_session) { create_drawing_session }
  let(:model) { create_user }

  def prepare_model
    grant_model_access(drawing_session, model)
    sign_in(model)
  end

  def book(date = '2026-11-16', user: model, at: drawing_session)
    track_booking(BookingMutation.new(drawing_session: at, user: user).book(date: date))
  end

  it 'distinguishes booked, available, and blocked dates for guests and session managers' do
    prepare_model
    book
    organizer = create_user
    grant_coordinator_access(drawing_session, organizer)
    delete session_path
    [nil, organizer].each do |viewer|
      sign_in(viewer) if viewer
      get drawing_session_path(drawing_session)
      booked = response.parsed_body.at_css('[data-date="2026-11-16"]')
      expect(booked['class']).to eq('booked')
      expect(booked.css('.status-label').map(&:text)).to eq(['Unconfirmed'])
      expect(booked.at_css('.status-label-warning').text).to eq('Unconfirmed')
      expect(booked.css('form')).to be_empty
      expect(response.parsed_body.at_css('[data-date="2026-11-23"]')['class']).to eq('available')
      expect(response.parsed_body.at_css('[data-date="2026-11-23"] .status-label-success').text).to eq('Available')
      expect(response.parsed_body.at_css('[data-date="2026-11-17"]')['class']).to eq('blocked')
    end
  end

  it 'distinguishes the usual session time from the actual booking time on cancellation and model lists' do
    prepare_model
    drawing_session.update!(start_time: '19:15')
    track_record(DrawingSessionScheduleException.create!(drawing_session: drawing_session, date: Date.new(2026, 11, 16),
                                                         mode: 'open', start_time: '20:00', reason: 'Later drawing.'))
    original = book
    get cancellation_drawing_session_model_booking_path(drawing_session, original)
    expect(response.body).to include('Monday at 7:15 PM (America/New_York)', '8:00 PM EST')
    grant_coordinator_access(drawing_session, model)
    get drawing_session_models_path(drawing_session)
    expect(response.body).to include('Monday at 7:15 PM (America/New_York)', '8:00 PM EST')
  end

  it 'renders an independently navigable calendar without changing booking actions' do
    prepare_model
    get drawing_session_path(drawing_session, month: '2026-12')
    calendar = response.parsed_body.at_css('[data-calendar]')
    expect(calendar.at_css('[data-calendar-month]').text).to eq('December 2026')
    expect(calendar.css('a[data-calendar-navigation]').pluck('href'))
      .to eq([drawing_session_path(drawing_session, month: '2026-11'),
              drawing_session_path(drawing_session, month: '2027-01')])
    expect(calendar.css('form').pluck('action').uniq).to eq([drawing_session_model_bookings_path(drawing_session)])
    expect(response.parsed_body.at_css('script[defer]')).to be_present
  end

  it 'keeps enhanced month navigation and replacement dates scoped to the current change form' do
    prepare_model
    original = book('2026-11-23')
    get edit_drawing_session_model_booking_path(drawing_session, original, month: '2026-12')
    calendar = response.parsed_body.at_css('[data-calendar]')
    expect(calendar.css('a[data-calendar-navigation]').pluck('href'))
      .to eq([edit_drawing_session_model_booking_path(drawing_session, original, month: '2026-11'),
              edit_drawing_session_model_booking_path(drawing_session, original, month: '2027-01')])
    expect(calendar.css('button[form]').pluck('form').uniq).to eq(['booking-change-form'])
    expect(calendar.css('form')).to be_empty
    expect(response.parsed_body.at_css('#booking-change-form')).to be_present
  end

  it 'requires authentication, session access, and a model membership before booking' do
    create_user
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-11-16' }
    expect(response).to redirect_to(new_session_path)
    sign_in(model)
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-11-16' }
    expect(response).to have_http_status(:not_found)
    grant_coordinator_access(drawing_session, model)
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-11-16' }
    expect(response).to have_http_status(:forbidden)
    expect(drawing_session.model_bookings).to be_empty
  end

  it 'books a nearby date and blocks further bookings while offering organizer contact and cancellation' do
    prepare_model
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-11-16', user_id: create_user.id }
    booking = track_booking(drawing_session.model_bookings.first)
    expect(booking.user_id).to eq(model.id)
    follow_redirect!
    expect(response.body).to include('Your posing date is booked.', 'Your Upcoming Booking',
                                     'Contact an Organizer Before Rescheduling', 'Cancel Booking')
    expect(response.body).not_to include('Change Date')
    expect(response.parsed_body.css('.calendar form')).to be_empty
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-11-23' }
    follow_redirect!
    expect(response.body).to include('You already have an upcoming booking')
    expect(drawing_session.model_bookings.count).to eq(1)
  end

  it 'rejects malformed, past, non-posing, and out-of-horizon dates on the server' do
    prepare_model
    ['invalid', '2026-11-09', '2026-11-17', '2027-05-17', nil].each do |date|
      post drawing_session_model_bookings_path(drawing_session), params: { date: date }
      follow_redirect!
      expect(response.body).to include('Choose an available date')
      expect(drawing_session.model_bookings).to be_empty
    end
  end

  it 'explains a date taken after the calendar loaded and refreshes the same month without a second booking' do
    prepare_model
    get drawing_session_path(drawing_session, month: '2026-12')
    expect(response.parsed_body.at_css('[data-date="2026-12-07"]')['class']).to eq('available')
    other = create_user
    grant_model_access(drawing_session, other)
    winner = book('2026-12-07', user: other)
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-12-07' }
    expect(response).to redirect_to(drawing_session_path(drawing_session, month: '2026-12'))
    follow_redirect!
    expect(response.body).to include('someone else just booked that date', 'Please choose another available date.')
    expect(response.parsed_body.at_css('[data-date="2026-12-07"]')['class']).to eq('booked')
    expect(drawing_session.model_bookings.pluck(:id)).to eq([winner.id])
    expect(ModelBookingClaim.where(drawing_session_id: drawing_session.id).pluck(:model_booking_id)).to eq([winner.id])
  end

  it 'reschedules with an explanation while preserving and linking both records' do
    prepare_model
    original = book('2026-11-23')
    get edit_drawing_session_model_booking_path(drawing_session, original)
    expect(response.body).to include('Change Your Posing Date', 'booking-change-form',
                                     'Plans changed? Not a problem. Tell us, then choose an available date below.')
    patch drawing_session_model_booking_path(drawing_session, original),
          params: { date: '2026-11-30', reason: 'Travel plans changed.', booking_version: original.lock_version }
    replacement = track_booking(drawing_session.model_bookings.where(previous_booking_id: original.id).first)
    expect(original.reload).to have_attributes(date: Date.new(2026, 11, 23), status: 'rescheduled',
                                               reason: 'Travel plans changed.', changed_by_id: model.id)
    expect(replacement.date).to eq(Date.new(2026, 11, 30))
    follow_redirect!
    expect(response.body).to include('Rescheduled', 'Moved from 2026-11-23', 'Travel plans changed.', 'Unconfirmed')
  end

  it 'keeps the original booking if a requested replacement date is occupied' do
    prepare_model
    original = book('2026-11-23')
    other = create_user
    grant_model_access(drawing_session, other)
    book('2026-11-30', user: other)
    patch drawing_session_model_booking_path(drawing_session, original),
          params: { date: '2026-11-30', reason: 'Need another date.', booking_version: original.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('someone else just booked that date')
    expect(response.parsed_body.at_css('#reason').text.strip).to eq('Need another date.')
    expect(original.reload.status).to eq('confirmed')
    expect(drawing_session.model_bookings.count).to eq(2)
    expect(ModelBookingClaim.find_by(user_id: model.id).model_booking_id).to eq(original.id)
  end

  it 'requires explanations and keeps month navigation on the change form after errors' do
    prepare_model
    original = book('2026-11-23')
    patch drawing_session_model_booking_path(drawing_session, original),
          params: { date: '2026-11-30', reason: ' ', booking_version: original.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Please tell us what changed')
    expect(response.parsed_body.at_css('nav[aria-label="Calendar months"] a')['href'])
      .to start_with(edit_drawing_session_model_booking_path(drawing_session, original))
    post cancel_drawing_session_model_booking_path(drawing_session, original),
         params: { reason: '', booking_version: original.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(original.reload.status).to eq('confirmed')
  end

  it 'rejects missing and malformed booking versions without changing the reservation' do
    prepare_model
    original = book('2026-11-23')
    [nil, '', 'not-a-version', '-1', '00'].each do |version|
      patch drawing_session_model_booking_path(drawing_session, original),
            params: { date: '2026-11-30', reason: 'Travel.', booking_version: version }
      expect(response).to redirect_to(drawing_session_path(drawing_session))
      expect(flash[:alert]).to include('changed while you were editing')
    end
    expect(original.reload).to have_attributes(status: 'confirmed', lock_version: 0)
    expect(drawing_session.model_bookings.count).to eq(1)
  end

  it 'retains a canceled booking and explanation when the model books a different day' do
    prepare_model
    original = book
    get cancellation_drawing_session_model_booking_path(drawing_session, original)
    expect(response.body).to include('Cancel Your Booking')
    post cancel_drawing_session_model_booking_path(drawing_session, original),
         params: { reason: 'A family commitment.', booking_version: original.lock_version }
    expect(original.reload).to have_attributes(status: 'canceled', reason: 'A family commitment.')
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-11-23' }
    replacement = track_booking(drawing_session.model_bookings.where(status: 'confirmed').first)
    expect(replacement.id).not_to eq(original.id)
    follow_redirect!
    expect(response.body).to include('2026-11-16', 'Canceled', 'A family commitment.', '2026-11-23', 'Unconfirmed')
    post cancel_drawing_session_model_booking_path(drawing_session, original),
         params: { reason: 'Overwrite history', booking_version: original.lock_version }
    expect(response).to redirect_to(drawing_session_path(drawing_session))
    expect(flash[:alert]).to include('changed while you were editing')
    expect(original.reload.reason).to eq('A family commitment.')
  end

  it 'never exposes another model history or permits changing another user or session booking' do
    prepare_model
    original = book
    other = create_user(name: 'Another Model')
    grant_model_access(drawing_session, other)
    sign_in(other)
    get drawing_session_path(drawing_session)
    expect(response.body).to include(model.public_name)
    expect(response.body).not_to include(model.email, 'Change Date')
    get edit_drawing_session_model_booking_path(drawing_session, original)
    expect(response).to have_http_status(:not_found)
    post cancel_drawing_session_model_booking_path(drawing_session, original),
         params: { reason: 'Forbidden', booking_version: original.lock_version }
    expect(response).to have_http_status(:not_found)
    expect(original.reload.status).to eq('confirmed')
  end

  it 'lets scoped organizers see session history without granting model booking privileges' do
    prepare_model
    original = book
    organizer = create_user(name: 'Session Organizer')
    grant_coordinator_access(drawing_session, organizer)
    sign_in(organizer)
    get drawing_session_path(drawing_session)
    expect(response.body).to include('Session Booking History', model.name, original.date.iso8601)
    expect(response.parsed_body.css('.calendar form')).to be_empty
    get drawing_session_path(create_drawing_session)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Session Booking History', 'Manage Schedule')
  end

  it 'honors existing reservations after session weekdays or horizon settings change' do
    prepare_model
    original = book('2026-11-23')
    drawing_session.update!(available_weekdays: ['2'])
    get drawing_session_path(drawing_session)
    expect(response.body).to include('Your Upcoming Booking', 'Change Date', 'Cancel Booking')
    expect(original.reload.status).to eq('confirmed')
    patch drawing_session_model_booking_path(drawing_session, original),
          params: { date: '2026-11-24', reason: 'New session weekday.', booking_version: original.lock_version }
    replacement = track_booking(drawing_session.model_bookings.where(previous_booking_id: original.id).first)
    expect(replacement.date).to eq(Date.new(2026, 11, 24))
  end

  context 'with a short-notice booking' do
    let(:original) { book }
    let(:organizer) { create_user(name: 'Drawing Organizer', phone: '+12125551234') }

    before do
      prepare_model
      original
      grant_coordinator_access(drawing_session, organizer)
    end

    it 'shows organizer contacts instead of the form and calendar and rejects direct submissions' do
      get edit_drawing_session_model_booking_path(drawing_session, original, month: '2026-12')
      expect(response.parsed_body.at_css('.rescheduling-notice').text).to include(organizer.name)
      expect(response.parsed_body.at_css("a[href='mailto:#{organizer.email}']")).to be_present
      expect(response.parsed_body.at_css('a[href="tel:+12125551234"]')).to be_present
      expect(response.parsed_body.at_css('#booking-change-form')).to be_nil
      expect(response.parsed_body.at_css('[data-calendar]')).to be_nil
      patch drawing_session_model_booking_path(drawing_session, original),
            params: { date: '2026-11-23', reason: 'Plans changed.', booking_version: original.lock_version }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Please contact an organizer before rescheduling', organizer.email)
      expect(original.reload.status).to eq('confirmed')
      expect(drawing_session.model_bookings.count).to eq(1)
      expect(ModelBookingClaim.find_by(model_booking_id: original.id).date).to eq(original.date)
    end

    it 'keeps contact details private and excludes inactive and other sessions organizers' do
      inactive = create_user(active: false, phone: '+12125554321')
      outsider = create_user(phone: '+12125555678')
      grant_coordinator_access(drawing_session, inactive)
      grant_coordinator_access(create_drawing_session, outsider)
      get drawing_session_path(drawing_session)
      expect(response.body).to include(organizer.email, organizer.phone)
      expect(response.body).not_to include(inactive.email, inactive.phone, outsider.email, outsider.phone)
      delete session_path
      get drawing_session_path(drawing_session)
      expect(response.body).not_to include(organizer.email, organizer.phone, 'rescheduling-notice')
    end
  end
end
