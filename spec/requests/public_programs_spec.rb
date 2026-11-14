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
    expect(response.parsed_body.css('.calendar form, .calendar button:not(.copy-button)')).to be_empty
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
                                       'Public Participant', 'Fallback Participant')
      expect(response.body).not_to include(hidden.name, hidden.email, hidden.phone, hidden.id.to_s,
                                           'private_participant')
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
    expect(response.parsed_body.at_css('[data-date="2026-11-23"]').text).to include('Unconfirmed')
    expect(response.body).not_to include('Fallback Participant', 'public_participant')
  end

  it 'announces private participants anonymously to guests and other participants' do
    booking = scheduled_booking('2026-11-16', name: 'Private Account', display_name: 'Hidden Alias',
                                              instagram_handle: '@private_participant', instagram_tagging_allowed: true,
                                              public_profile_private: true)
    [nil, create_user].each do |viewer|
      grant_participant_access(program, viewer) if viewer
      sign_in(viewer) if viewer
      get program_path(program, section: 'calendar')
      expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include('To be announced')
      expect(response.body).not_to include(booking.user.name, 'Hidden Alias', 'private_participant',
                                           booking.user.email, booking.user.id.to_s)
    end
  end

  it 'lets authorized managers identify private participants in the calendar and retained history' do
    participant = private_booking.user
    participant.update!(public_profile_private: true, instagram_tagging_allowed: true)
    sign_in(create_user(roles: ['system_admin']))
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include(participant.name)
    get program_path(program, section: 'history')
    history = response.parsed_body.at_xpath('//section[h2="Program Booking History"]')
    expect(history.text).to include(participant.name)
    expect(response.body).not_to include('private_participant')
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
