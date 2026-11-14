# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public session calendars', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:drawing_session) { create_drawing_session(instructions: 'Private door instructions.', model_pay: 321) }
  let(:private_booking) do
    scheduled_booking('2026-11-16', name: 'Private Account Name', display_name: 'Public Artist',
                                    phone: '+12125551234', instagram_handle: '@private_model')
  end
  let(:tagged_booking) do
    scheduled_booking('2026-11-23', name: 'Fallback Artist', instagram_handle: '@public_model',
                                    instagram_tagging_allowed: true)
  end

  def scheduled_booking(date, at: drawing_session, **attributes)
    user = create_user(**attributes)
    grant_model_access(at, user)
    track_booking(BookingMutation.new(drawing_session: at, user: user).book(date: date))
  end

  def expect_public_only
    expect(response.body).not_to include(drawing_session.instructions, 'Model Pay', 'Booking History',
                                         'Manage Schedule', 'Invite a Model', 'Your Upcoming Booking')
    expect(response.parsed_body.css('.calendar form, .calendar button')).to be_empty
  end

  it 'renders only the calendar for a matching public navigation context' do
    private_booking
    get drawing_session_path(drawing_session)
    context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    get drawing_session_path(drawing_session), params: { month: '2026-12' },
                                               headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('[data-calendar-month]').text).to eq('December 2026')
    expect(response.parsed_body.at_css('header, main')).to be_nil
    expect(response.headers['Vary']).to include('X-Posebook-Calendar-Context')
    expect_public_only
  end

  it 'returns the full authorized page when a manager context becomes stale or is forged' do
    private_booking
    organizer = create_user
    access = grant_coordinator_access(drawing_session, organizer)
    sign_in(organizer)
    get drawing_session_path(drawing_session)
    context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    get drawing_session_path(drawing_session), headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response.parsed_body.at_css('header, main')).to be_nil
    expect(response.body).to include('Schedule Model')
    access.pull(roles: 'session_coordinator')
    get drawing_session_path(drawing_session), headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response.parsed_body.at_css('header.site-header')).to be_present
    expect_public_only
    delete session_path
    get drawing_session_path(drawing_session), headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response.parsed_body.at_css('header.site-header')).to be_present
    expect_public_only
  end

  it 'allows guests through slugs, shortcuts, and IDs while exposing only public model identity' do
    hidden = private_booking.user
    tagged_booking
    [drawing_session_path(drawing_session), drawing_session_path(drawing_session),
     drawing_session_path(drawing_session.id)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(
        response.body
      ).to include(drawing_session.name, drawing_session.address, 'Monday at 6:30 PM', 'Public Artist',
                   'Fallback Artist')
      expect(response.body).not_to include(hidden.name, hidden.email, hidden.phone, hidden.id.to_s, 'private_model')
      link = response.parsed_body.at_css('a[href="https://www.instagram.com/public_model/"]')
      expect(link.text).to eq('@public_model')
      expect(link['target']).to eq('_blank')
      expect(link['rel'].split).to include('noopener', 'noreferrer')
      expect_public_only
    end
  end

  it 'does not turn a signed-in visitor into a member or expose private endpoints through forged parameters' do
    private_booking
    visitor = create_user
    sign_in(visitor)
    get drawing_session_path(drawing_session), params: { session_coordinator: '1', can_book: '1', public_view: 'false' }
    expect(response).to have_http_status(:ok)
    expect_public_only
    [drawing_session_models_path(drawing_session), drawing_session_schedule_path(drawing_session),
     new_drawing_session_model_invitation_path(drawing_session)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    post drawing_session_model_bookings_path(drawing_session), params: { date: '2026-11-30' }
    expect(response).to have_http_status(:not_found)
    expect(DrawingSessionMembership.where(user_id: visitor.id)).to be_empty
  end

  it 'hides canceled records, other sessions, and internal schedule explanations' do
    canceled = scheduled_booking('2026-11-16', display_name: 'Canceled Model')
    BookingMutation.new(drawing_session: drawing_session, user: canceled.user).cancel(booking: canceled,
                                                                                      reason: 'Private cancellation.')
    scheduled_booking('2026-11-23', at: create_drawing_session, display_name: 'Other Session Model')
    track_record(DrawingSessionScheduleException.create!(drawing_session: drawing_session, date: Date.new(2026, 11, 30),
                                                         mode: 'closed', reason: 'Private closure explanation.'))
    track_record(
      DrawingSessionScheduleException.create!(drawing_session: drawing_session, date: Date.new(2026, 11, 17),
                                              mode: 'open', start_time: '20:00', reason: 'Private extra drawing.')
    )
    get drawing_session_path(drawing_session)
    expect(response.body).not_to include('Canceled Model', 'Other Session Model', 'Private cancellation.',
                                         'Private closure explanation.', 'Private extra drawing.')
    expect(response.parsed_body.at_css('[data-date="2026-11-30"]').text).to include('Closed')
    expect(response.parsed_body.at_css('[data-date="2026-11-17"]').text).to include('8:00 PM')
    expect_public_only
  end

  it 'keeps inactive accounts reserved without publishing their identity or Instagram' do
    tagged_booking.user.update!(active: false)
    get drawing_session_path(drawing_session)
    expect(response.parsed_body.at_css('[data-date="2026-11-23"]').text).to include('Booked')
    expect(response.body).not_to include('Fallback Artist', 'public_model')
  end

  it 'announces private models anonymously to guests and other models' do
    booking = scheduled_booking('2026-11-16', name: 'Private Account', display_name: 'Hidden Alias',
                                              instagram_handle: '@private_model', instagram_tagging_allowed: true,
                                              public_profile_private: true)
    [nil, create_user].each do |viewer|
      grant_model_access(drawing_session, viewer) if viewer
      sign_in(viewer) if viewer
      get drawing_session_path(drawing_session)
      expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include('To be announced')
      expect(response.body).not_to include(booking.user.name, 'Hidden Alias', 'private_model',
                                           booking.user.email, booking.user.id.to_s)
    end
  end

  it 'lets authorized managers identify private models in the calendar and retained history' do
    model = private_booking.user
    model.update!(public_profile_private: true, instagram_tagging_allowed: true)
    sign_in(create_user(roles: ['system_admin']))
    get drawing_session_path(drawing_session)
    expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include(model.name)
    history = response.parsed_body.at_xpath('//section[h2="Session Booking History"]')
    expect(history.text).to include(model.name)
    expect(response.body).not_to include('private_model')
  end

  it 'uses current public preferences and removes Instagram immediately after tagging is turned off' do
    user = tagged_booking.user
    get drawing_session_path(drawing_session)
    expect(response.body).to include('https://www.instagram.com/public_model/')
    user.update!(display_name: 'New Public Name', instagram_tagging_allowed: false)
    get drawing_session_path(drawing_session, month: '2026-11')
    expect(response.body).to include('New Public Name')
    expect(response.body).not_to include('Fallback Artist', 'public_model', user.email)
  end

  it 'retains personal booking information for members and management only for managers' do
    sign_in(private_booking.user)
    get drawing_session_path(drawing_session)
    expect(response.body).to include(drawing_session.instructions, 'Model Pay', 'Your Booking History',
                                     'Your Upcoming Booking')
    expect(response.body).not_to include('Session Booking History', 'Manage Schedule')
    member_context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    sign_in(create_user(roles: ['system_admin']))
    get drawing_session_path(drawing_session)
    expect(response.body).to include(drawing_session.instructions, 'Model Pay', 'Session Booking History',
                                     'Manage Schedule')
    expect(response.parsed_body.at_css('[data-calendar]')['data-calendar-context']).not_to eq(member_context)
  end
end
