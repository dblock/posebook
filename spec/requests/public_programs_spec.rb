# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public session calendars', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) do
    create_program(instructions: 'Private door instructions.', pay: 321,
                   time_zone: 'America/New_York', start_time: '18:30')
  end
  let(:private_booking) do
    scheduled_booking('2026-11-16', name: 'Private Account Name', display_name: 'Public Participant',
                                    phone: '+12125551234', instagram_handle: '@private_participant')
  end
  let(:tagged_booking) do
    scheduled_booking('2026-11-23', name: 'Fallback Participant', instagram_handle: '@public_participant',
                                    instagram_tagging_allowed: true)
  end

  def scheduled_booking(date, at: program, **attributes)
    user = create_user(**attributes)
    grant_participant_access(at, user)
    track_booking(BookingMutation.new(program: at, user: user).book(date: date))
  end

  def expect_public_only
    expect(response.body).not_to include(program.instructions, 'Pay', 'Booking History',
                                         'Manage Schedule', 'Invite a Participant', 'Your Upcoming Booking')
    expect(response.parsed_body.css('.calendar form, .calendar button')).to be_empty
  end

  def schedule_exception(date, **attributes)
    track_record(ProgramScheduleException.create!(program: program, date: Date.iso8601(date), mode: 'closed',
                                                  reason: 'Private schedule explanation.', **attributes))
  end

  it 'shows the venue directly after the next session to guests and signed-in visitors' do
    [nil, create_user].each do |viewer|
      sign_in(viewer) if viewer
      get program_path(program)
      card = response.parsed_body.at_css('.next-session + .venue-card')
      expect(card).to be_present
      expect(card.text).to include(program.venue.name, program.venue.address)
      expect(card.at_css('h2 a')['href']).to eq(venue_path(program.venue))
      expect(card.next_element.key?('data-calendar')).to be(true)
      expect_public_only
    end
  end

  it 'summarizes the next session using only public identity and consented Instagram' do
    program.update!(end_time: '21:00')
    user = private_booking.user
    user.update!(instagram_tagging_allowed: true)
    get program_path(program)
    summary = response.parsed_body.at_css('.next-session')
    expect(summary.text).to include('Monday, November 16, 2026', '6:30 PM - 9:00 PM (2 hours 30 min)',
                                    'America/New_York', 'Public Participant')
    expect(summary.at_css('time')['datetime']).to eq('2026-11-16T23:30:00Z')
    expect(summary.css('table, dt, dd')).to be_empty
    expect(summary.at_css('.booked-participant a[target="_blank"]')['href'])
      .to eq('https://www.instagram.com/private_participant/')
    expect(summary.at_css('.booked-participant a')['href']).to eq(participant_path(user))
    expect(response.body).not_to include(user.name, user.email, user.phone)
    expect_public_only
  end

  it 'keeps inactive next-session identities anonymous even in the manager overview' do
    user = private_booking.user
    user.update!(instagram_tagging_allowed: true, active: false)
    [nil, create_user, create_user(roles: ['system_admin'])].each do |viewer|
      grant_participant_access(program, viewer) if viewer && !viewer.system_admin?
      sign_in(viewer) if viewer
      get program_path(program)
      summary = response.parsed_body.at_css('.next-session')
      expect(summary.text).to include("#{program.participant_label} to be announced")
      expect(summary.to_html).not_to include(user.name, user.display_name, user.email, user.id.to_s,
                                             'private_participant')
    end
  end

  it 'refreshes public identity and tagging choices in the next-session summary on each request' do
    user = private_booking.user
    user.update!(instagram_tagging_allowed: true)
    get program_path(program)
    expect(response.parsed_body.at_css('.next-session').text).to include('@private_participant')
    user.update!(display_name: 'Current Public Name', instagram_tagging_allowed: false)
    get program_path(program)
    summary = response.parsed_body.at_css('.next-session')
    expect(summary.text).to include('Current Public Name')
    expect(summary.text).not_to include('Public Participant', 'private_participant')
  end

  it 'uses the configured participant label for unbooked sessions and hidden public identities' do
    program.update!(participant_label: 'Model')
    get program_path(program)
    expect(response.parsed_body.at_css('.next-session').text).to include('Model to be announced')
    booking = scheduled_booking('2026-11-16', display_name: '')
    get program_path(program)
    summary = response.parsed_body.at_css('.next-session')
    expect(summary.text).to include('Model to be announced')
    expect(summary.at_css("a[href='#{participant_path(booking.user)}']")).to be_nil
  end

  it 'announces the scheduled date without treating canceled or foreign bookings as its participant' do
    booking = private_booking
    BookingMutation.new(program: program, user: booking.user).cancel(booking: booking, reason: 'Private cancellation.')
    scheduled_booking('2026-11-16', at: create_program, display_name: 'Other Program Participant')
    get program_path(program)
    summary = response.parsed_body.at_css('.next-session')
    expect(summary.text).to include('Monday, November 16, 2026', "#{program.participant_label} to be announced")
    expect(summary.text).not_to include('Public Participant', 'Other Program Participant', 'Private cancellation.')
  end

  it 'respects closures and one-off opening times instead of jumping to the next booked date' do
    tagged_booking
    schedule_exception('2026-11-16')
    schedule_exception('2026-11-17', mode: 'open', start_time: '20:00', end_time: '22:00')
    get program_path(program)
    summary = response.parsed_body.at_css('.next-session')
    expect(summary.text).to include('Tuesday, November 17, 2026', '8:00 PM - 10:00 PM (2 hours)',
                                    "#{program.participant_label} to be announced")
    expect(response.body).not_to include('Private schedule explanation.', 'Fallback Participant')
  end

  it 'finds next-month sessions and their public booking independently of an overview month parameter' do
    schedule_exception('2026-12-07')
    scheduled_booking('2026-12-14', display_name: 'December Participant')
    travel_to Time.utc(2026, 11, 30, 23, 31)
    get program_path(program, section: 'view', month: '2027-02')
    summary = response.parsed_body.at_css('.next-session')
    expect(summary.text).to include('Monday, December 14, 2026', 'December Participant')
    expect(summary.text).not_to include('View Calendar')
    expect(response.body).not_to include('Private schedule explanation.')
  end

  it 'shows an honest empty state when all dates within the booking window are closed' do
    program.update!(booking_horizon_months: 1, program_label: 'Session')
    %w[2026-11-16 2026-11-23 2026-11-30 2026-12-07].each { |date| schedule_exception(date) }
    get program_path(program)
    summary = response.parsed_body.at_css('.next-session')
    expect(summary.text).to include('No scheduled sessions within the booking window.')
    expect(summary.at_css('time')).to be_nil
    expect(response.parsed_body.at_css('[data-calendar]')).to be_present
  end

  it 'renders only the calendar for a matching public navigation context' do
    private_booking
    get program_path(program, section: 'calendar')
    context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    get program_path(program), params: { month: '2026-12' },
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
    access = grant_coordinator_access(program, organizer)
    sign_in(organizer)
    get program_path(program, section: 'calendar')
    context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    get program_path(program), headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response.parsed_body.at_css('header, main')).to be_nil
    expect(response.body).to include('Schedule Participant')
    access.pull(roles: 'program_coordinator')
    get program_path(program), headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response.parsed_body.at_css('header.site-header')).to be_present
    expect_public_only
    delete session_path
    get program_path(program), headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response.parsed_body.at_css('header.site-header')).to be_present
    expect_public_only
  end

  it 'allows guests through slugs, shortcuts, and IDs while exposing only public participant identity' do
    hidden = private_booking.user
    tagged_booking
    [program_path(program, section: 'calendar'), program_path(program.id, section: 'calendar')].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(program.name, 'Monday at 6:30 PM',
                                       'Public Participant', 'To be announced')
      expect(response.body).not_to include(hidden.name, hidden.email, hidden.phone, 'Fallback Participant',
                                           'private_participant')
      expect(response.parsed_body.at_css("a[href='#{participant_path(hidden)}']").text).to eq('Public Participant')
      expect(response.body).not_to include(tagged_booking.user.id.to_s)
      link = response.parsed_body.at_css('a[href="https://www.instagram.com/public_participant/"]')
      expect(link.text).to eq('@public_participant')
      expect(link['target']).to eq('_blank')
      expect(link['rel'].split).to include('noopener', 'noreferrer')
      expect_public_only
    end
  end

  it 'does not turn a signed-in visitor into a member or expose private endpoints through forged parameters' do
    private_booking
    visitor = create_user
    sign_in(visitor)
    get program_path(program), params: { program_coordinator: '1', can_book: '1', public_view: 'false' }
    expect(response).to have_http_status(:ok)
    expect_public_only
    [program_participants_path(program), program_schedule_path(program),
     new_program_participant_invitation_path(program)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    post program_bookings_path(program), params: { date: '2026-11-30' }
    expect(response).to have_http_status(:not_found)
    expect(ProgramMembership.where(user_id: visitor.id)).to be_empty
  end

  it 'hides canceled records, other sessions, and internal schedule explanations' do
    canceled = scheduled_booking('2026-11-16', display_name: 'Canceled Participant')
    BookingMutation.new(program: program, user: canceled.user).cancel(booking: canceled,
                                                                      reason: 'Private cancellation.')
    scheduled_booking('2026-11-23', at: create_program, display_name: 'Other Program Participant')
    track_record(ProgramScheduleException.create!(program: program, date: Date.new(2026, 11, 30),
                                                  mode: 'closed', reason: 'Private closure explanation.'))
    track_record(
      ProgramScheduleException.create!(program: program, date: Date.new(2026, 11, 17),
                                       mode: 'open', start_time: '20:00', reason: 'Private extra booking.')
    )
    get program_path(program, section: 'calendar')
    expect(response.body).not_to include('Canceled Participant', 'Other Program Participant', 'Private cancellation.',
                                         'Private closure explanation.', 'Private extra booking.')
    expect(response.parsed_body.at_css('[data-date="2026-11-30"]').text).to include('Closed')
    expect(response.parsed_body.at_css('[data-date="2026-11-17"]').text).to include('8:00 PM')
    expect_public_only
  end

  it 'keeps inactive accounts reserved without publishing their identity or Instagram' do
    tagged_booking.user.update!(active: false)
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.at_css('[data-date="2026-11-23"]').text).to include('Booked')
    expect(response.body).not_to include('Fallback Participant', 'public_participant')
  end

  it 'shows only the active participant public name and consented Instagram to visitors' do
    booking = scheduled_booking('2026-11-16', name: 'Private Account', display_name: 'Hidden Alias',
                                              instagram_handle: '@private_participant', instagram_tagging_allowed: true)
    [nil, create_user].each do |viewer|
      grant_participant_access(program, viewer) if viewer
      sign_in(viewer) if viewer
      get program_path(program, section: 'calendar')
      expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include('Hidden Alias',
                                                                                      '@private_participant')
      expect(response.body).not_to include(booking.user.name, booking.user.email)
    end
  end

  it 'lets managers identify participants with blank display names in the calendar and retained history' do
    participant = private_booking.user
    participant.update!(display_name: nil, instagram_tagging_allowed: true)
    sign_in(create_user(roles: ['system_admin']))
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include(participant.name)
    expect(response.body).not_to include(participant.email)
    get program_path(program, section: 'history')
    history = response.parsed_body.at_xpath('//section[h2="Program Booking History"]')
    expect(history.text).to include(participant.name)
    expect(history.at_css('.participant-identity a[target="_blank"]').text).to eq('@private_participant')
  end

  it 'uses current public preferences and removes Instagram immediately after tagging is turned off' do
    user = tagged_booking.user
    get program_path(program, section: 'calendar')
    expect(response.body).to include('https://www.instagram.com/public_participant/')
    user.update!(display_name: 'New Public Name', instagram_tagging_allowed: false)
    get program_path(program, month: '2026-11')
    expect(response.body).to include('New Public Name')
    expect(response.body).not_to include('Fallback Participant', 'public_participant', user.email)
  end

  it 'retains personal booking information for members and management only for managers' do
    sign_in(private_booking.user)
    get program_path(program)
    expect(response.body).to include(program.instructions, 'Pay', 'Your Upcoming Booking')
    expect(response.body).not_to include('Program Booking History', 'Manage Schedule')
    get program_path(program, section: 'history')
    expect(response.body).to include('Your Booking History')
    get program_path(program, section: 'calendar')
    member_context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    sign_in(create_user(roles: ['system_admin']))
    get program_path(program)
    expect(response.body).to include(program.instructions, 'Pay')
    get program_path(program, section: 'history')
    expect(response.body).to include('Program Booking History')
    get program_path(program, section: 'calendar')
    expect(response.body).to include('Manage Schedule')
    expect(response.parsed_body.at_css('[data-calendar]')['data-calendar-context']).not_to eq(member_context)
  end
end
