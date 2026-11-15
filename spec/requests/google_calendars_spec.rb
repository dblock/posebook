# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Google Calendar connections', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:program) { create_program }
  let(:organizer) { create_user }
  let(:calendar_id) { 'synthetic-calendar@example.test' }
  let(:client) { instance_double(Google::Apis::CalendarV3::CalendarService) }
  let(:auth) do
    instance_double(Google::Auth::UserRefreshCredentials, :code= => nil, fetch_access_token!: {},
                                                          refresh_token: 'synthetic-refresh-token')
  end

  around do |example|
    names = %w[GOOGLE_CALENDAR_CLIENT_ID GOOGLE_CALENDAR_CLIENT_SECRET GOOGLE_CALENDAR_REDIRECT_URI]
    old = ENV.to_h.slice(*names)
    ENV.update(names.zip(['synthetic-id', 'synthetic-secret', 'http://localhost:3000/google_calendar/callback']).to_h)
    example.run
  ensure
    names.each { |name| old.key?(name) ? ENV[name] = old[name] : ENV.delete(name) }
  end

  before { grant_coordinator_access(program, organizer) }
  after { GoogleCalendarSync.where(program_id: program.id).delete_all }

  def authorize
    sign_in(organizer)
    post program_google_calendar_path(program),
         params: { google_calendar: { calendar_id: calendar_id, private_calendar: '1' } }
    Rack::Utils.parse_query(URI.parse(response.location).query)['state']
  end

  def mock_exchange(role: 'writer')
    allow(GoogleCalendarConnection).to receive_messages(credentials: auth, service: client)
    entry = Google::Apis::CalendarV3::CalendarListEntry.new(access_role: role)
    allow(client).to receive(:get_calendar_list).with(calendar_id).and_return(entry)
  end

  def response_connection
    connection = GoogleCalendarConnection.new(program: program, connected_by: organizer, calendar_id: calendar_id)
    connection.refresh_token = 'synthetic-refresh-token'
    track_record(connection.tap(&:save!))
  end

  def response_booking
    participant = create_user
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant)
                   .book(date: Date.current.next_occurring(:monday).iso8601))
  end

  def response_snapshot
    connection = response_connection
    booking = response_booking
    sync = GoogleCalendarSync.find(booking.id)
    sync.set(fingerprint: 'sent', rsvp_fingerprint: 'sent', rsvp_booking_id: booking.id,
             rsvp_calendar_id: calendar_id, rsvp_status: 'declined', rsvp_checked_at: Time.current)
    [connection, booking, sync]
  end

  it 'shows separate one-word Google response labels to managers without changing booking labels' do
    _, booking, sync = response_snapshot
    sign_in(organizer)
    { 'needsAction' => 'Pending', 'accepted' => 'Accepted', 'tentative' => 'Tentative',
      'declined' => 'Declined' }.each do |status, label|
      sync.set(rsvp_status: status)
      get program_path(program, section: 'calendar')
      cell = response.parsed_body.at_css("[data-date=\"#{booking.date.iso8601}\"]")
      expect(cell.at_css('.google-calendar-rsvp .status-label').text).to eq(label)
      expect(cell.css('.status-label').map(&:text)).to eq(['Booked', label])
      expect(cell.at_css('.google-calendar-rsvp .status-label')['title']).to include('last checked')
    end
    get program_path(program, section: 'history')
    expect(response.parsed_body.at_css('.google-calendar-rsvp .status-label').text).to eq('Declined')
    get edit_program_organizer_booking_path(program, booking)
    expect(response.parsed_body.at_css('.google-calendar-rsvp .status-label').text).to eq('Declined')
    expect(booking.reload.display_status).to eq('Booked')
  end

  it 'places Google responses inline beside booking badges without a visible prefix' do
    _, booking, = response_snapshot
    sign_in(organizer)
    [program_path(program, section: 'calendar'), program_path(program, section: 'history'),
     program_participants_path(program), edit_program_organizer_booking_path(program, booking)].each do |path|
      get path
      rsvp = response.parsed_body.at_css('span.google-calendar-rsvp')
      expect(rsvp.text.strip).to eq('Declined')
      expect(rsvp.previous_element.text).to eq('Booked')
      expect(rsvp.at_css('.status-label')['aria-label']).to include('Google RSVP')
    end
  end

  it 'keeps Google responses out of public and participant views' do
    _, booking, = response_snapshot
    [nil, booking.user, create_user].each do |viewer|
      sign_in(viewer) if viewer
      get program_path(program, section: 'calendar')
      expect(response.parsed_body.at_css('.google-calendar-rsvp')).to be_nil
    end
    sign_in(booking.user)
    get program_path(program, section: 'history')
    expect(response.parsed_body.at_css('.google-calendar-rsvp')).to be_nil
  end

  it 'hides responses belonging to an old payload or booking and disconnected or unauthorized calendars' do
    connection, booking, sync = response_snapshot
    sign_in(create_user(roles: ['system_admin']))
    sync.set(rsvp_fingerprint: 'old-payload')
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.at_css('.google-calendar-rsvp')).to be_nil
    sync.set(rsvp_fingerprint: 'sent', rsvp_booking_id: BSON::ObjectId.new)
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.at_css('.google-calendar-rsvp')).to be_nil
    sync.set(rsvp_booking_id: booking.id)
    connection.update!(enabled: false)
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.at_css('.google-calendar-rsvp')).to be_nil
    connection.update!(enabled: true)
    program.memberships.coordinators.first.pull(roles: 'program_coordinator')
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.at_css('.google-calendar-rsvp')).to be_nil
  end

  it 'restricts connection settings to the program managers' do
    get program_google_calendar_path(program)
    expect(response).to redirect_to(new_session_path)
    sign_in(create_user)
    get program_google_calendar_path(program)
    expect(response).to have_http_status(:not_found)
    sign_in(organizer)
    get program_google_calendar_path(program)
    expect(response.body).to include('Google Calendar', 'private')
    expect(response.parsed_body.at_css('[name="google_calendar[private_calendar]"][type="checkbox"]')['required'])
      .to be_present
  end

  it 'requires explicit private-calendar confirmation before redirecting to Google' do
    sign_in(organizer)
    post program_google_calendar_path(program), params: { google_calendar: { calendar_id: calendar_id } }
    expect(response).to redirect_to(program_google_calendar_path(program))
    expect(GoogleCalendarConnection.count).to eq(0)
  end

  it 'connects with encrypted credentials, queues existing bookings, and rejects callback replay' do
    participant = create_user
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program,
                                      user: participant).book(date: Date.current.next_occurring(:monday).iso8601))
    state = authorize
    mock_exchange
    get google_calendar_callback_path, params: { state: state, code: 'synthetic-code' }
    connection = track_record(GoogleCalendarConnection.find_by(program_id: program.id))
    expect(connection.encrypted_refresh_token).not_to include('synthetic-refresh-token')
    expect(connection).to have_attributes(calendar_id: calendar_id, connected_by_id: organizer.id)
    expect(GoogleCalendarSync.where(program_id: program.id).count).to eq(1)
    expect(response).to redirect_to(program_google_calendar_path(program))
    get google_calendar_callback_path, params: { state: state, code: 'synthetic-code' }
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects tampered state without contacting Google' do
    authorize
    allow(GoogleCalendarConnection).to receive(:service)
    get google_calendar_callback_path, params: { state: 'wrong', code: 'synthetic-code' }
    expect(response).to have_http_status(:forbidden)
    expect(GoogleCalendarConnection.count).to eq(0)
    expect(GoogleCalendarConnection).not_to have_received(:service)
  end

  it 'rechecks management permission and rejects read-only Google calendars' do
    state = authorize
    mock_exchange(role: 'reader')
    get google_calendar_callback_path, params: { state: state, code: 'synthetic-code' }
    expect(response).to redirect_to(program_google_calendar_path(program))
    expect(GoogleCalendarConnection.count).to eq(0)
  end

  it 'rechecks management permission when authorization returns' do
    state = authorize
    program.memberships.coordinators.first.pull(roles: 'program_coordinator')
    get google_calendar_callback_path, params: { state: state, code: 'synthetic-code' }
    expect(response).to have_http_status(:not_found)
  end

  it 'clears stored credentials on disconnect without deleting external events' do
    connection = GoogleCalendarConnection.new(program: program, connected_by: organizer, calendar_id: calendar_id)
    connection.refresh_token = 'synthetic-refresh-token'
    track_record(connection.tap(&:save!))
    sign_in(organizer)
    delete program_google_calendar_path(program)
    expect(connection.reload).to have_attributes(enabled: false, encrypted_refresh_token: nil)
    expect(response).to redirect_to(program_google_calendar_path(program))
  end

  it 'rejects expired authorization without contacting Google' do
    state = authorize
    allow(GoogleCalendarConnection).to receive(:service)
    travel 11.minutes
    get google_calendar_callback_path, params: { state: state, code: 'synthetic-code' }
    expect(response).to have_http_status(:forbidden)
    expect(GoogleCalendarConnection).not_to have_received(:service)
  end
end
