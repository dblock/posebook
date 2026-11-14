# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Attendance confirmation', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:participant) { create_user(public_profile_private: true) }
  let(:booking) do
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-23'))
  end

  before do
    booking
    travel_to Time.utc(2026, 11, 16, 15)
    sign_in(participant)
  end

  def confirm_booking(**attributes)
    post confirm_program_booking_path(program, booking),
         params: { booking_version: booking.lock_version }.merge(attributes)
  end

  def history_status(viewer, heading, column)
    sign_in(viewer)
    get program_path(program)
    history = response.parsed_body.at_xpath("//section[h2='#{heading}']")
    row = history.css('tbody tr').find { |entry| entry.at_css('td').text.start_with?(booking.date.iso8601) }
    row.at_css("td:nth-child(#{column})")
  end

  def close_confirmed_booking(status)
    confirm_booking
    mutation = BookingMutation.new(program: program, user: participant)
    attributes = { booking: booking.reload, reason: 'Travel plans changed.' }
    return mutation.cancel(**attributes) if status == 'canceled'

    track_booking(mutation.change(**attributes, date: '2026-11-30'))
  end

  it 'offers confirmation and the usual rescheduling workflow seven days before posing' do
    get program_path(program)
    expect(response.body).to include('I&#39;ll be there!', 'I can no longer make it.')
    confirm_booking
    follow_redirect!
    expect(response.body).to include('You&#39;re confirmed')
    expect(response.parsed_body.at_css('.calendar .attendance-confirmed').text).to eq('Confirmed')
    day = response.parsed_body.at_css(".calendar [data-date='#{booking.date.iso8601}']")
    expect(day.css('.status-label').map(&:text)).to eq(['Confirmed'])
    expect(response.parsed_body.at_css('form[action$="/confirm"]')).to be_nil
    expect(booking.reload.attendance_confirmed_by_id).to eq(participant.id)
  end

  it 'shows confirmed only once in the status cell of both participant and session history' do
    confirm_booking
    organizer = create_user
    grant_coordinator_access(program, organizer)
    [[participant, 'Your Booking History', 2],
     [organizer, 'Session Booking History', 3]].each do |viewer, heading, column|
      status = history_status(viewer, heading, column)
      expect(status.at_css('.attendance-confirmed').text).to eq('Confirmed')
      expect(status.css('.status-label').map(&:text)).to eq(['Confirmed'])
      expect(status.text.scan(/\bConfirmed\b/).size).to eq(1)
    end
  end

  it 'shows one unconfirmed label before the confirmation window on calendars and history' do
    travel_to Time.utc(2026, 11, 13, 15)
    organizer = create_user
    grant_coordinator_access(program, organizer)
    [[participant, 'Your Booking History', 2],
     [organizer, 'Session Booking History', 3]].each do |viewer, heading, column|
      status = history_status(viewer, heading, column)
      expect(status.css('.status-label').map(&:text)).to eq(['Unconfirmed'])
      day = response.parsed_body.at_css(".calendar [data-date='#{booking.date.iso8601}']")
      expect(day.css('.status-label').map(&:text)).to eq(['Unconfirmed'])
    end
  end

  %w[canceled rescheduled].each do |state|
    it "does not show attendance confirmation on #{state} history for either viewer" do
      close_confirmed_booking(state)
      organizer = create_user
      grant_coordinator_access(program, organizer)
      [[participant, 'Your Booking History', 2],
       [organizer, 'Session Booking History', 3]].each do |viewer, heading, column|
        status = history_status(viewer, heading, column)
        expect(status.text.strip).to eq(state.humanize)
        expect(status.css('.status-label').map(&:text)).to eq([state.humanize])
        expect(status.at_css('.attendance-confirmed')).to be_nil
        expect(response.body).to include('Confirmed on ')
      end
    end
  end

  it 'shows only completed while retaining confirmation in the historical explanation' do
    confirm_booking
    travel_to booking.ends_at
    status = history_status(participant, 'Your Booking History', 2)
    expect(status.css('.status-label').map(&:text)).to eq(['Completed'])
    expect(status.at_css('.attendance-confirmed')).to be_nil
    expect(response.body).to include('Confirmed on ')
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
    grant_coordinator_access(program, organizer)
    travel_to Time.utc(2026, 11, 18, 5)
    get program_path(program)
    expect(response.body).to include('Please contact an organizer ASAP', organizer.email, organizer.phone)
    expect(response.body).not_to include('I can no longer make it.')
    patch program_booking_path(program, booking),
          params: { date: '2026-11-30', reason: 'Travel.', booking_version: booking.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(booking.reload.status).to eq('confirmed')
    confirm_booking
    follow_redirect!
    expect(response.body).not_to include('Please contact an organizer ASAP', 'Attendance not confirmed')
  end

  it 'shows urgent follow-up on manager calendars and rosters, not public calendars' do
    organizer = create_user
    grant_coordinator_access(program, organizer)
    travel_to Time.utc(2026, 11, 18, 5)
    sign_in(organizer)
    [program_path(program), program_participants_path(program)].each do |path|
      get path
      expect(response.body).to include('Unconfirmed', 'Please contact an organizer ASAP')
      warning = response.parsed_body.at_css('.attendance-warning')
      expect(warning['role']).to eq('status')
      expect(warning['class']).not_to include('status-label')
      selector = ".calendar [data-date='#{booking.date.iso8601}'], .participant-roster td:nth-child(2)"
      cell = response.parsed_body.at_css(selector)
      expect(cell.css('.status-label').map(&:text)).to eq(['Unconfirmed'])
    end
    delete session_path
    get program_path(program)
    expect(response.body).not_to include('Attendance not confirmed', 'follow up ASAP', 'Edit Booking')
  end

  it 'publishes a positive confirmation without revealing a private participant or confirmation history' do
    confirm_booking
    delete session_path
    get program_path(program)
    expect(response.body).to include('To be announced')
    expect(response.parsed_body.at_css('.calendar .attendance-confirmed').text).to eq('Confirmed')
    expect(response.body).not_to include(participant.name, participant.email, 'Session Booking History',
                                         'I&#39;ll be there!')
  end

  it 'does not let another participant or a different session confirm the booking' do
    other = create_user
    grant_participant_access(program, other)
    sign_in(other)
    confirm_booking
    expect(response).to have_http_status(:not_found)
    other_program = create_program
    grant_participant_access(other_program, participant)
    sign_in(participant)
    post confirm_program_booking_path(other_program, booking)
    expect(response).to have_http_status(:not_found)
    expect(booking.reload.attendance_confirmed?).to be(false)
  end

  it 'permits an already booked paused participant to confirm without granting repeat booking access' do
    program.memberships.participants.find_by(user_id: participant.id).update!(participant_paused: true,
                                                                              participant_pause_reason: 'On a break.')
    confirm_booking
    expect(booking.reload.attendance_confirmed?).to be(true)
    get program_path(program)
    expect(response.body).not_to include('I can no longer make it.')
  end

  it 'reloads stale private summaries when confirmation changes during calendar navigation' do
    get program_path(program)
    context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    confirm_booking
    get program_path(program, month: '2026-12')
    expect(response.parsed_body.at_css('[data-calendar]')['data-calendar-context']).not_to eq(context)
  end

  it 'does not confirm a changed drawing time from an old confirmation button' do
    organizer = create_user
    grant_coordinator_access(program, organizer)
    get program_path(program)
    version = response.parsed_body.at_css('input[name="booking_version"]')['value']
    track_record(ProgramScheduleMutation.new(program: program, user: organizer).call(
                   date: booking.date.iso8601, mode: 'open', start_time: '20:00', reason: 'Later drawing.'
                 ))
    confirm_booking(booking_version: version)
    expect(response).to redirect_to(program_path(program))
    expect(flash[:alert]).to include('changed while you were editing')
    expect(booking.reload.attendance_confirmed?).to be(false)
    expect(booking.time_changes.size).to eq(1)
  end
end
