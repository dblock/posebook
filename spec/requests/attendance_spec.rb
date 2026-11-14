# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Attendance confirmation', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:model) { create_user(public_profile_private: true) }
  let(:booking) do
    grant_model_access(venue, model)
    track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-23'))
  end

  before do
    booking
    travel_to Time.utc(2026, 11, 16, 15)
    sign_in(model)
  end

  def confirm_booking(**attributes)
    post confirm_venue_model_booking_path(venue, booking),
         params: { booking_version: booking.lock_version }.merge(attributes)
  end

  def history_status(viewer, heading, column)
    sign_in(viewer)
    get venue_path(venue)
    history = response.parsed_body.at_xpath("//section[h2='#{heading}']")
    row = history.css('tbody tr').find { |entry| entry.at_css('td').text.start_with?(booking.date.iso8601) }
    row.at_css("td:nth-child(#{column})")
  end

  def close_confirmed_booking(status)
    confirm_booking
    mutation = BookingMutation.new(venue: venue, user: model)
    attributes = { booking: booking.reload, reason: 'Travel plans changed.' }
    return mutation.cancel(**attributes) if status == 'canceled'

    track_booking(mutation.change(**attributes, date: '2026-11-30'))
  end

  it 'offers confirmation and the usual rescheduling workflow seven days before posing' do
    get venue_path(venue)
    expect(response.body).to include('I&#39;ll be there!', 'I can no longer make it.')
    confirm_booking
    follow_redirect!
    expect(response.body).to include('You&#39;re confirmed')
    expect(response.parsed_body.at_css('.calendar .attendance-confirmed').text).to eq('Confirmed')
    expect(response.parsed_body.at_css('form[action$="/confirm"]')).to be_nil
    expect(booking.reload.attendance_confirmed_by_id).to eq(model.id)
  end

  it 'shows confirmed only once in the status cell of both model and venue history' do
    confirm_booking
    organizer = create_user
    grant_schedule_access(venue, organizer)
    [[model, 'Your Booking History', 2], [organizer, 'Venue Booking History', 3]].each do |viewer, heading, column|
      status = history_status(viewer, heading, column)
      expect(status.at_css('.attendance-confirmed').text).to eq('Confirmed')
      expect(status.text.scan(/\bConfirmed\b/).size).to eq(1)
    end
  end

  %w[canceled rescheduled].each do |state|
    it "does not show attendance confirmation on #{state} history for either viewer" do
      close_confirmed_booking(state)
      organizer = create_user
      grant_schedule_access(venue, organizer)
      [[model, 'Your Booking History', 2], [organizer, 'Venue Booking History', 3]].each do |viewer, heading, column|
        status = history_status(viewer, heading, column)
        expect(status.text.strip).to eq(state.humanize)
        expect(status.at_css('.attendance-confirmed')).to be_nil
        expect(response.body).to include('Confirmed on ')
      end
    end
  end

  it 'keeps the historical confirmation badge on completed sessions' do
    confirm_booking
    travel_to booking.ends_at
    status = history_status(model, 'Your Booking History', 2)
    expect(status.text).to include('Completed', 'Confirmed')
    expect(status.at_css('.attendance-confirmed').text).to eq('Confirmed')
  end

  it 'rejects early confirmation and makes a repeated or forged request to clear confirmation harmless' do
    travel_to Time.utc(2026, 11, 16, 4, 59, 59)
    confirm_booking
    expect(booking.reload.attendance_confirmed?).to be(false)
    travel_to Time.utc(2026, 11, 16, 5)
    2.times { confirm_booking(attendance: 'unconfirmed') }
    expect(booking.reload.attendance_changes.size).to eq(1)
    expect(booking.attendance_confirmed?).to be(true)
  end

  it 'removes the decline option five days out, blocks stale changes, and requests urgent private contact' do
    organizer = create_user(phone: '+12125551234')
    grant_schedule_access(venue, organizer)
    travel_to Time.utc(2026, 11, 18, 5)
    get venue_path(venue)
    expect(response.body).to include('Please contact an organizer ASAP', organizer.email, organizer.phone)
    expect(response.body).not_to include('I can no longer make it.')
    patch venue_model_booking_path(venue, booking),
          params: { date: '2026-11-30', reason: 'Travel.', booking_version: booking.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(booking.reload.status).to eq('confirmed')
    confirm_booking
    follow_redirect!
    expect(response.body).not_to include('Please contact an organizer ASAP', 'Attendance not confirmed')
  end

  it 'shows urgent follow-up on manager calendars and rosters, not public calendars' do
    organizer = create_user
    grant_schedule_access(venue, organizer)
    travel_to Time.utc(2026, 11, 18, 5)
    sign_in(organizer)
    [venue_path(venue), venue_models_path(venue)].each do |path|
      get path
      expect(response.body).to include('Attendance not confirmed - follow up ASAP')
    end
    delete session_path
    get venue_path(venue)
    expect(response.body).not_to include('Attendance not confirmed', 'follow up ASAP', 'Edit Booking')
  end

  it 'publishes a positive confirmation without revealing a private model or confirmation history' do
    confirm_booking
    delete session_path
    get venue_path(venue)
    expect(response.body).to include('To be announced')
    expect(response.parsed_body.at_css('.calendar .attendance-confirmed').text).to eq('Confirmed')
    expect(response.body).not_to include(model.name, model.email, 'Venue Booking History', 'I&#39;ll be there!')
  end

  it 'does not let another model or a different venue confirm the booking' do
    other = create_user
    grant_model_access(venue, other)
    sign_in(other)
    confirm_booking
    expect(response).to have_http_status(:not_found)
    other_venue = create_venue
    grant_model_access(other_venue, model)
    sign_in(model)
    post confirm_venue_model_booking_path(other_venue, booking)
    expect(response).to have_http_status(:not_found)
    expect(booking.reload.attendance_confirmed?).to be(false)
  end

  it 'permits an already booked paused model to confirm without granting repeat booking access' do
    venue.memberships.models.find_by(user_id: model.id).update!(model_paused: true, model_pause_reason: 'On a break.')
    confirm_booking
    expect(booking.reload.attendance_confirmed?).to be(true)
    get venue_path(venue)
    expect(response.body).not_to include('I can no longer make it.')
  end

  it 'reloads stale private summaries when confirmation changes during calendar navigation' do
    get venue_path(venue)
    context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    confirm_booking
    get venue_path(venue, month: '2026-12')
    expect(response.parsed_body.at_css('[data-calendar]')['data-calendar-context']).not_to eq(context)
  end

  it 'does not confirm a changed drawing time from an old confirmation button' do
    organizer = create_user
    grant_schedule_access(venue, organizer)
    get venue_path(venue)
    version = response.parsed_body.at_css('input[name="booking_version"]')['value']
    track_record(VenueScheduleMutation.new(venue: venue, user: organizer).call(
                   date: booking.date.iso8601, mode: 'open', start_time: '20:00', reason: 'Later drawing.'
                 ))
    confirm_booking(booking_version: version)
    expect(response).to redirect_to(venue_path(venue))
    expect(flash[:alert]).to include('changed while you were editing')
    expect(booking.reload.attendance_confirmed?).to be(false)
    expect(booking.time_changes.size).to eq(1)
  end
end
