# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Calendar session states', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:drawing_session) { create_drawing_session }

  def day(date)
    response.parsed_body.at_css("[data-date=\"#{date}\"]")
  end

  def historical_booking(date, at: drawing_session, status: 'confirmed', **attributes)
    user = create_user(**attributes)
    date = Date.iso8601(date)
    start = DrawingSessionSchedule.local_start(date, '20:45', at.time_zone)
    track_booking(ModelBooking.create!(drawing_session: at, user: user, date: date, time_zone: at.time_zone,
                                       starts_at: start, ends_at: (date + 1).in_time_zone(at.time_zone).utc,
                                       created_at: start - 1.week, status: status,
                                       reason: status == 'confirmed' ? nil : 'Private cancellation.'))
  end

  def exception(date, mode, start_time: nil)
    now = Time.current
    travel_to Time.utc(2026, 11, 1, 15)
    track_record(
      DrawingSessionScheduleException.create!(drawing_session: drawing_session, date: Date.iso8601(date), mode: mode,
                                              start_time: start_time, reason: 'Private historical explanation.')
    )
  ensure
    travel_to now
  end

  def organizer_for(at = drawing_session)
    user = create_user
    grant_coordinator_access(at, user)
    user
  end

  def reserve(date)
    user = create_user
    grant_model_access(drawing_session, user)
    track_booking(BookingMutation.new(drawing_session: drawing_session, user: user).book(date: date))
  end

  it 'shows No Session without a redundant Blocked label and leaves past non-session cells entirely blank' do
    get drawing_session_path(drawing_session)
    expect(day('2026-11-17').css('span').text).to eq('No Session')
    expect(day('2026-11-17').text).not_to include('Blocked', 'Not a posing day')
    expect(day('2026-11-10').children).to be_empty
    expect(day('2026-11-09').text).to include('6:30 PM', 'Past Session')
    expect(day('2026-11-09').css('form, button')).to be_empty
  end

  it 'honors historical openings and closures without publishing their explanations' do
    exception('2026-11-09', 'closed')
    exception('2026-11-10', 'open', start_time: '21:15')
    get drawing_session_path(drawing_session)
    expect(day('2026-11-09').children).to be_empty
    expect(day('2026-11-10').text).to include('9:15 PM', 'Past Session')
    expect(response.body).not_to include('Private historical explanation.')
  end

  it 'keeps a completed session and saved time visible even after its regular weekday changes' do
    booking = historical_booking('2026-11-09', display_name: 'Past Public Artist')
    drawing_session.update!(available_weekdays: ['2'])
    get drawing_session_path(drawing_session)
    expect(day('2026-11-09').text).to include('Completed', '8:45 PM', 'Past Public Artist')
    expect(day('2026-11-09').css('form, button')).to be_empty
    expect(response.body).not_to include(booking.user.email, 'Your Upcoming Booking')
  end

  it 'applies current public-profile privacy and Instagram preferences to past sessions' do
    public_booking = historical_booking('2026-11-02', display_name: 'Past Public Artist',
                                                      instagram_handle: 'past_artist', instagram_tagging_allowed: true)
    hidden = historical_booking('2026-11-09', name: 'Private Past Artist', public_profile_private: true,
                                              instagram_handle: 'hidden_past_artist', instagram_tagging_allowed: true)
    get drawing_session_path(drawing_session)
    expect(day('2026-11-02').text).to include('Past Public Artist', '@past_artist')
    expect(day('2026-11-09').text).to include('To be announced')
    expect(response.body).not_to include(hidden.user.name, 'hidden_past_artist', hidden.user.email)
    public_booking.user.update!(instagram_tagging_allowed: false)
    get drawing_session_path(drawing_session)
    expect(response.body).not_to include('@past_artist')
  end

  it 'does not publish canceled or foreign-session history when showing past sessions' do
    historical_booking('2026-11-02', status: 'canceled', display_name: 'Canceled Past Artist')
    historical_booking('2026-11-09', at: create_drawing_session, display_name: 'Foreign Past Artist')
    get drawing_session_path(drawing_session)
    expect(day('2026-11-02').text).to include('Past Session')
    expect(response.body).not_to include('Canceled Past Artist', 'Foreign Past Artist', 'Private cancellation.')
  end

  it 'shows past sessions in leading neighboring-month cells without granting past management controls' do
    historical_booking('2026-11-30', display_name: 'Previous Month Artist')
    travel_to Time.utc(2026, 12, 4, 15)
    sign_in(organizer_for)
    get drawing_session_path(drawing_session)
    expect(day('2026-11-30').text).to include('Completed', 'Previous Month Artist')
    expect(day('2026-11-30').css('a, form, button')).to be_empty
    expect(day('2026-11-29').children).to be_empty
    expect(day('2026-12-01').children).to be_empty
  end

  it 'keeps a completed booking separate from the model upcoming summary and fresh booking permission' do
    booking = historical_booking('2026-11-09')
    grant_model_access(drawing_session, booking.user)
    sign_in(booking.user)
    get drawing_session_path(drawing_session)
    expect(response.body).not_to include('Your Upcoming Booking', 'You are already scheduled')
    expect(day('2026-11-16').at_css('form')).to be_present
    expect(day('2026-11-09').css('form, button')).to be_empty
  end

  it 'uses date-only Future placeholders outside the horizon and neighboring months for guests and models' do
    drawing_session.update!(booking_horizon_months: 1)
    model = create_user
    grant_model_access(drawing_session, model)
    [nil, model].each do |viewer|
      sign_in(viewer) if viewer
      get drawing_session_path(drawing_session, month: '2026-12')
      %w[2026-11-30 2026-12-14].each do |date|
        expect(day(date).css('span').text).to eq('Future')
        expect(day(date).css('strong, small, form, button, a')).to be_empty
      end
    end
  end

  it 'shows organizers actual neighboring-month sessions with scoped booking and day controls' do
    booking = reserve('2026-12-28')
    sign_in(organizer_for)
    get drawing_session_path(drawing_session, month: '2027-01')
    expect(day('2026-12-28').text).to include('Booked', '6:30 PM', booking.user.public_name)
    expect(day('2026-12-28').at_css('a')['href']).to eq(edit_drawing_session_organizer_booking_path(drawing_session,
                                                                                                    booking))
    expect(day('2027-02-01').text).to include('Available', '6:30 PM', 'Schedule Model', 'Edit Day')
    path = day('2027-02-01').at_css('a')['href']
    expect(path).to eq(new_drawing_session_organizer_booking_path(drawing_session, date: '2027-02-01'))
    get path
    expect(response.parsed_body.at_css('#booking_date')['value']).to eq('2027-02-01')
  end

  it 'does not let organizer neighboring-month controls bypass the booking horizon or session scope' do
    drawing_session.update!(booking_horizon_months: 1)
    sign_in(organizer_for)
    get drawing_session_path(drawing_session, month: '2026-12')
    expect(day('2026-12-14').css('span').text).to eq('Future')
    expect(day('2026-12-14').css('a, form, button')).to be_empty
    sign_in(organizer_for(create_drawing_session))
    get drawing_session_path(drawing_session, month: '2026-12', session_coordinator: '1')
    expect(day('2026-11-30').css('span').text).to eq('Future')
    expect(day('2026-11-30').css('a, form, button')).to be_empty
  end
end
