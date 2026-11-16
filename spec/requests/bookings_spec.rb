# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Participant bookings', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(time_zone: 'America/New_York', start_time: '18:30') }
  let(:participant) { create_user }

  def prepare_participant
    grant_participant_access(program, participant)
    sign_in(participant)
  end

  def book(date = '2026-11-16', user: participant, at: program)
    track_booking(BookingMutation.new(program: at, user: user).book(date: date))
  end

  def confirmed_booking(date, **attributes)
    { date: date, confirmed: '1', schedule_revision: program.reload.schedule_revision.to_s }.merge(attributes)
  end

  it 'shows only your upcoming bookings on home, ordered by saved time, with venue details and button actions' do
    prepare_participant
    later = book('2026-12-07')
    earlier_program = create_program(time_zone: 'America/New_York', start_time: '20:00', end_time: '22:00')
    grant_participant_access(earlier_program, participant)
    earlier = book('2026-11-23', at: earlier_program)
    other = create_user
    grant_participant_access(earlier_program, other)
    book('2026-11-30', user: other, at: earlier_program)
    get bookings_profile_path
    cards = response.parsed_body.css('.upcoming-booking')
    expect(cards.pluck('aria-labelledby'))
      .to eq(["upcoming-booking-#{earlier.id}", "upcoming-booking-#{later.id}"])
    expect(cards.first.text).to include('November 23, 2026', '8:00 PM - 10:00 PM', earlier_program.address)
    expect(cards.first.at_css('.venue-google-maps')['href']).to eq(earlier_program.venue.google_maps_location_url)
    expect(cards.first.css('.booking-actions .button-link').map(&:text)).to eq(['Reschedule', 'Cancel Booking'])
    expect(response.body).not_to include(other.email, 'November 30, 2026', 'Confirmation opens',
                                         'You can have one upcoming booking')
  end

  it 'groups the date, status, and actions inside the same card on session View and Calendar pages' do
    prepare_participant
    later = book('2026-12-07')
    [program_path(program), program_path(program, section: 'calendar')].each do |path|
      get path
      card = response.parsed_body.at_css('.upcoming-booking')
      expect(card.at_css('time').text).to include('December 07, 2026', '6:30 PM')
      expect(card.at_css('time')['datetime']).to eq(later.scheduled_start.iso8601)
      expect(card.css('.booking-actions .button-link').map(&:text)).to eq(['Reschedule', 'Cancel Booking'])
      expect(response.body).not_to include('Confirmation opens', 'You can have one upcoming booking')
    end
  end

  it 'omits canceled and completed bookings from the homepage' do
    prepare_participant
    later = book('2026-12-07')
    earlier_program = create_program
    grant_participant_access(earlier_program, participant)
    earlier = book('2026-11-23', at: earlier_program)
    BookingMutation.new(program: program, user: participant).cancel(booking: later, reason: 'Plans changed.')
    travel_to earlier.ends_at
    get bookings_profile_path
    expect(response.parsed_body.css('.upcoming-booking')).to be_empty
  end

  it 'asks for confirmation before booking and lets the participant cancel without a reservation' do
    prepare_participant
    post program_bookings_path(program), params: { date: '2026-11-16' }
    expect(response.body).to include('Confirm Your Booking', 'November 16, 2026', '6:30 PM', 'America/New_York')
    form = response.parsed_body.at_css("form[action='#{program_bookings_path(program)}']")
    expect(form.at_css('[name="date"]')['value']).to eq('2026-11-16')
    expect(form.at_css('[name="confirmed"]')['value']).to eq('1')
    expect(form.at_css('[name="schedule_revision"]')['value']).to eq(program.reload.schedule_revision.to_s)
    expect(program.bookings).to be_empty
    get response.parsed_body.css('a').find { |link| link.text == 'Cancel' }['href']
    expect(program.bookings).to be_empty
    expect(response.parsed_body.at_css('[data-date="2026-11-16"] form')).to be_present
    post program_bookings_path(program), params: { date: '2026-11-16' }
    revision = response.parsed_body.at_css('[name="schedule_revision"]')['value']
    post program_bookings_path(program),
         params: { date: '2026-11-16', confirmed: '1', schedule_revision: revision }
    booking = track_booking(program.bookings.first)
    expect(booking).to have_attributes(user_id: participant.id, date: Date.new(2026, 11, 16))
  end

  it 'rejects missing or stale schedule revisions instead of booking a changed time' do
    prepare_participant
    post program_bookings_path(program), params: { date: '2026-11-16', confirmed: '1' }
    expect(response).to redirect_to(program_path(program))
    expect(program.bookings).to be_empty
    post program_bookings_path(program), params: { date: '2026-11-16' }
    revision = response.parsed_body.at_css('[name="schedule_revision"]')['value']
    ProgramSettingsUpdate.new(program: program, user: create_user(roles: ['system_admin'])).call(start_time: '19:30')
    post program_bookings_path(program),
         params: { date: '2026-11-16', confirmed: '1', schedule_revision: revision }
    expect(response).to redirect_to(program_path(program))
    expect(flash[:alert]).to include('changed while you were editing')
    expect(program.bookings).to be_empty
  end

  it 'distinguishes booked, available, and blocked dates for guests and session managers' do
    prepare_participant
    book
    organizer = create_user
    grant_coordinator_access(program, organizer)
    delete session_path
    [nil, organizer].each do |viewer|
      sign_in(viewer) if viewer
      get program_path(program, section: 'calendar')
      booked = response.parsed_body.at_css('[data-date="2026-11-16"]')
      expect(booked['class']).to eq('booked')
      expect(booked.css('.status-label').map(&:text)).to eq(['Booked'])
      expect(booked.at_css('.status-label-warning').text).to eq('Booked')
      expect(booked.css('form')).to be_empty
      expect(response.parsed_body.at_css('[data-date="2026-11-23"]')['class']).to eq('available')
      expect(response.parsed_body.at_css('[data-date="2026-11-23"] .status-label-success').text).to eq('Available')
      expect(response.parsed_body.at_css('[data-date="2026-11-17"]')['class']).to eq('blocked')
    end
  end

  it 'distinguishes the usual session time from the actual booking time on cancellation and participant lists' do
    prepare_participant
    program.update!(start_time: '19:15')
    track_record(ProgramScheduleException.create!(program: program, date: Date.new(2026, 11, 16),
                                                  mode: 'open', start_time: '20:00', reason: 'Later booking.'))
    original = book
    get cancellation_program_booking_path(program, original)
    expect(response.body).to include('Monday at 7:15 PM (America/New_York)', '8:00 PM EST')
    grant_coordinator_access(program, participant)
    get program_participants_path(program)
    expect(response.body).to include('Monday at 7:15 PM (America/New_York)', '8:00 PM EST')
  end

  it 'renders an independently navigable calendar without changing booking actions' do
    prepare_participant
    get program_path(program, month: '2026-12')
    calendar = response.parsed_body.at_css('[data-calendar]')
    expect(calendar.at_css('[data-calendar-month]').text).to eq('December 2026')
    expect(calendar.css('a[data-calendar-navigation]').pluck('href'))
      .to eq([program_path(program, month: '2026-11'),
              program_path(program, month: '2027-01')])
    expect(calendar.css('form').pluck('action').uniq).to eq([program_bookings_path(program)])
    expect(response.parsed_body.at_css('script[defer]')).to be_present
  end

  it 'keeps enhanced month navigation and replacement dates scoped to the current change form' do
    prepare_participant
    original = book('2026-11-23')
    get edit_program_booking_path(program, original, month: '2026-12')
    calendar = response.parsed_body.at_css('[data-calendar]')
    expect(calendar.css('a[data-calendar-navigation]').pluck('href'))
      .to eq([edit_program_booking_path(program, original, month: '2026-11'),
              edit_program_booking_path(program, original, month: '2027-01')])
    expect(calendar.css('button[form]').pluck('form').uniq).to eq(['booking-change-form'])
    expect(calendar.css('form')).to be_empty
    expect(response.parsed_body.at_css('#booking-change-form')).to be_present
  end

  it 'requires authentication, session access, and a participant membership before booking' do
    create_user
    post program_bookings_path(program), params: { date: '2026-11-16' }
    expect(response).to redirect_to(new_session_path)
    sign_in(participant)
    post program_bookings_path(program), params: { date: '2026-11-16' }
    expect(response).to have_http_status(:not_found)
    grant_coordinator_access(program, participant)
    post program_bookings_path(program), params: { date: '2026-11-16' }
    expect(response).to have_http_status(:forbidden)
    expect(program.bookings).to be_empty
  end

  it 'books a nearby date and blocks further bookings while offering organizer contact and cancellation' do
    prepare_participant
    post program_bookings_path(program), params: confirmed_booking('2026-11-16', user_id: create_user.id)
    booking = track_booking(program.bookings.first)
    expect(booking.user_id).to eq(participant.id)
    follow_redirect!
    expect(response.body).to include('Your program is booked.', 'Your Upcoming Booking',
                                     'Attendance Confirmation Needed', 'Cancel Booking')
    expect(response.body).not_to include('Reschedule')
    expect(response.parsed_body.css('.calendar form')).to be_empty
    get cancellation_program_booking_path(program, booking)
    expect(response.parsed_body.at_css('.rescheduling-notice h3').text).to eq('Contact an Organizer')
    post program_bookings_path(program), params: confirmed_booking('2026-11-23')
    follow_redirect!
    expect(response.body).to include('You already have an upcoming booking')
    expect(program.bookings.count).to eq(1)
  end

  it 'uses the configured session label in the booking confirmation message' do
    program.update!(program_label: 'Figure Drawing Session')
    prepare_participant
    post program_bookings_path(program), params: confirmed_booking('2026-11-23')
    track_booking(program.bookings.first)
    follow_redirect!
    expect(response.body).to include('Your figure drawing session is booked.')
  end

  it 'rejects malformed, past, non-participating, and out-of-horizon dates on the server' do
    prepare_participant
    ['invalid', '2026-11-09', '2026-11-17', '2027-05-17', nil].each do |date|
      post program_bookings_path(program), params: confirmed_booking(date)
      follow_redirect!
      expect(response.body).to include('Choose an available date')
      expect(program.bookings).to be_empty
    end
  end

  it 'explains a date taken after the calendar loaded and refreshes the same month without a second booking' do
    prepare_participant
    get program_path(program, month: '2026-12')
    expect(response.parsed_body.at_css('[data-date="2026-12-07"]')['class']).to eq('available')
    other = create_user
    grant_participant_access(program, other)
    winner = book('2026-12-07', user: other)
    post program_bookings_path(program), params: confirmed_booking('2026-12-07')
    expect(response).to redirect_to(program_path(program, month: '2026-12'))
    follow_redirect!
    expect(response.body).to include('someone else just booked that date', 'Please choose another available date.')
    expect(response.parsed_body.at_css('[data-date="2026-12-07"]')['class']).to eq('booked')
    expect(program.bookings.pluck(:id)).to eq([winner.id])
    expect(BookingClaim.where(program_id: program.id).pluck(:booking_id)).to eq([winner.id])
  end

  it 'reschedules with an explanation while preserving and linking both records' do
    prepare_participant
    original = book('2026-11-23')
    get edit_program_booking_path(program, original)
    expect(response.body).to include('Change Your Booking Date', 'booking-change-form',
                                     'Plans changed? Not a problem. Tell us, then choose an available date below.')
    patch program_booking_path(program, original),
          params: { date: '2026-11-30', reason: 'Travel plans changed.', booking_version: original.lock_version }
    replacement = track_booking(program.bookings.where(previous_booking_id: original.id).first)
    expect(original.reload).to have_attributes(date: Date.new(2026, 11, 23), status: 'rescheduled',
                                               reason: 'Travel plans changed.', changed_by_id: participant.id)
    expect(replacement.date).to eq(Date.new(2026, 11, 30))
    get program_path(program, section: 'history')
    expect(response.body).to include('Rescheduled', 'Moved from 2026-11-23', 'Travel plans changed.', 'Booked')
  end

  it 'keeps the original booking if a requested replacement date is occupied' do
    prepare_participant
    original = book('2026-11-23')
    other = create_user
    grant_participant_access(program, other)
    book('2026-11-30', user: other)
    patch program_booking_path(program, original),
          params: { date: '2026-11-30', reason: 'Need another date.', booking_version: original.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('someone else just booked that date')
    expect(response.parsed_body.at_css('#reason').text.strip).to eq('Need another date.')
    expect(original.reload.status).to eq('confirmed')
    expect(program.bookings.count).to eq(2)
    expect(BookingClaim.find_by(user_id: participant.id).booking_id).to eq(original.id)
  end

  it 'requires explanations and keeps month navigation on the change form after errors' do
    prepare_participant
    original = book('2026-11-23')
    patch program_booking_path(program, original),
          params: { date: '2026-11-30', reason: ' ', booking_version: original.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Please tell us what changed')
    expect(response.parsed_body.at_css('nav[aria-label="Calendar months"] a')['href'])
      .to start_with(edit_program_booking_path(program, original))
    post cancel_program_booking_path(program, original),
         params: { reason: '', booking_version: original.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    expect(original.reload.status).to eq('confirmed')
  end

  it 'rejects missing and malformed booking versions without changing the reservation' do
    prepare_participant
    original = book('2026-11-23')
    [nil, '', 'not-a-version', '-1', '00'].each do |version|
      patch program_booking_path(program, original),
            params: { date: '2026-11-30', reason: 'Travel.', booking_version: version }
      expect(response).to redirect_to(program_path(program))
      expect(flash[:alert]).to include('changed while you were editing')
    end
    expect(original.reload).to have_attributes(status: 'confirmed', lock_version: 0)
    expect(program.bookings.count).to eq(1)
  end

  it 'retains a canceled booking and explanation when the participant books a different day' do
    prepare_participant
    original = book
    get cancellation_program_booking_path(program, original)
    expect(response.body).to include('Cancel Your Booking')
    post cancel_program_booking_path(program, original),
         params: { reason: 'A family commitment.', booking_version: original.lock_version }
    expect(original.reload).to have_attributes(status: 'canceled', reason: 'A family commitment.')
    post program_bookings_path(program), params: confirmed_booking('2026-11-23')
    replacement = track_booking(program.bookings.where(status: 'confirmed').first)
    expect(replacement.id).not_to eq(original.id)
    get program_path(program, section: 'history')
    expect(response.body).to include('2026-11-16', 'Canceled', 'A family commitment.', '2026-11-23', 'Booked')
    post cancel_program_booking_path(program, original),
         params: { reason: 'Overwrite history', booking_version: original.lock_version }
    expect(response).to redirect_to(program_path(program))
    expect(flash[:alert]).to include('changed while you were editing')
    expect(original.reload.reason).to eq('A family commitment.')
  end

  it 'never exposes another participant history or permits changing another user or session booking' do
    prepare_participant
    original = book
    other = create_user(name: 'Another Participant')
    grant_participant_access(program, other)
    sign_in(other)
    get program_path(program, section: 'calendar')
    expect(response.body).to include(participant.public_name)
    expect(response.body).not_to include(participant.email, 'Reschedule')
    get edit_program_booking_path(program, original)
    expect(response).to have_http_status(:not_found)
    post cancel_program_booking_path(program, original),
         params: { reason: 'Forbidden', booking_version: original.lock_version }
    expect(response).to have_http_status(:not_found)
    expect(original.reload.status).to eq('confirmed')
  end

  it 'lets scoped organizers see session history without granting participant booking privileges' do
    prepare_participant
    original = book
    organizer = create_user(name: 'Program Organizer')
    grant_coordinator_access(program, organizer)
    sign_in(organizer)
    get program_path(program, section: 'history')
    expect(response.body).to include('Program Booking History', participant.name, original.date.iso8601)
    expect(response.parsed_body.css('.calendar form')).to be_empty
    get program_path(create_program)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Program Booking History', 'Manage Schedule')
  end

  it 'honors existing reservations after session weekdays or horizon settings change' do
    prepare_participant
    original = book('2026-11-23')
    program.update!(available_weekdays: ['2'])
    get program_path(program)
    expect(response.body).to include('Your Upcoming Booking', 'Reschedule', 'Cancel Booking')
    expect(original.reload.status).to eq('confirmed')
    patch program_booking_path(program, original),
          params: { date: '2026-11-24', reason: 'New session weekday.', booking_version: original.lock_version }
    replacement = track_booking(program.bookings.where(previous_booking_id: original.id).first)
    expect(replacement.date).to eq(Date.new(2026, 11, 24))
  end

  context 'with a short-notice booking' do
    let(:original) { book }
    let(:organizer) { create_user(name: 'Booking Organizer', phone: '+12125551234') }

    before do
      prepare_participant
      original
      grant_coordinator_access(program, organizer)
    end

    it 'shows organizer contacts instead of the form and calendar and rejects direct submissions' do
      get edit_program_booking_path(program, original, month: '2026-12')
      expect(response.parsed_body.at_css('.rescheduling-notice').text).to include(organizer.name)
      expect(response.parsed_body.at_css("a[href='mailto:#{organizer.email}']")).to be_present
      expect(response.parsed_body.at_css('a[href="tel:+12125551234"]')).to be_present
      expect(response.parsed_body.at_css('#booking-change-form')).to be_nil
      expect(response.parsed_body.at_css('[data-calendar]')).to be_nil
      patch program_booking_path(program, original),
            params: { date: '2026-11-23', reason: 'Plans changed.', booking_version: original.lock_version }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Please contact an organizer before rescheduling', organizer.email)
      expect(original.reload.status).to eq('confirmed')
      expect(program.bookings.count).to eq(1)
      expect(BookingClaim.find_by(booking_id: original.id).date).to eq(original.date)
    end

    it 'keeps contact details private and excludes inactive and other sessions organizers' do
      inactive = create_user(active: false, phone: '+12125554321')
      outsider = create_user(phone: '+12125555678')
      grant_coordinator_access(program, inactive)
      grant_coordinator_access(create_program, outsider)
      get program_path(program)
      expect(response.body).to include(organizer.email, organizer.phone)
      expect(response.body).not_to include(inactive.email, inactive.phone, outsider.email, outsider.phone)
      delete session_path
      get program_path(program)
      expect(response.body).not_to include(organizer.email, organizer.phone, 'rescheduling-notice')
    end
  end
end
