# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Booking details', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(time_zone: 'America/New_York', start_time: '18:30', end_time: '21:00') }
  let(:participant) { create_user(name: 'Studio Model') }
  let(:booking) do
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-23'))
  end

  def view_as(user)
    sign_in(user)
    get program_booking_path(program, booking)
  end

  it 'shows the participant their own booking with its venue and actions' do
    view_as(participant)
    expect(response).to have_http_status(:ok)
    page = response.parsed_body
    expect(page.at_css('h1').text).to eq('Your Booking')
    expect(page.at_css('.upcoming-booking-date').text).to include('Nov 23')
    expect(page.at_css('.upcoming-booking-date a')).to be_nil
    expect(page.css('.booking-actions a').map(&:text)).to include('Reschedule', 'Cancel Booking')
    expect(page.at_css('.venue-location').text).to include(program.venue.name)
    expect(response.body).not_to include(participant.email)
  end

  it 'shows program coordinators, venue coordinators, and system admins the participant and edit link' do
    program_coordinator = create_user
    grant_coordinator_access(program, program_coordinator)
    venue_coordinator = create_user
    grant_venue_access(program.venue, venue_coordinator)
    [program_coordinator, venue_coordinator, create_user(roles: ['system_admin'])].each do |viewer|
      view_as(viewer)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css('h1').text).to eq('Participant Booking')
      expect(response.body).to include(participant.email)
      expect(response.parsed_body.at_css("a[href='#{edit_program_organizer_booking_path(program, booking)}']"))
        .to be_present
    end
  end

  it "hides a booking from other participants, other programs' coordinators, and outsiders" do
    other_participant = create_user
    grant_participant_access(program, other_participant)
    other_coordinator = create_user
    grant_coordinator_access(create_program, other_coordinator)
    [other_participant, other_coordinator, create_user].each do |viewer|
      view_as(viewer)
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.at_css('.upcoming-booking, .booking-details')).to be_nil
    end
    sign_in(participant)
    get program_booking_path(program, BSON::ObjectId.new)
    expect(response).to have_http_status(:not_found)
  end

  it 'returns to the booking after signing in from an email link' do
    get program_booking_path(program, booking)
    expect(response).to redirect_to(new_session_path)
    sign_in(participant)
    expect(response).to redirect_to(program_booking_path(program, booking))
  end

  it 'links moved bookings in both directions for the participant' do
    replacement = track_booking(BookingMutation.new(program: program, user: participant)
                                                .change(booking: booking, date: '2026-11-30', reason: 'Travel',
                                                        version: booking.lock_version))
    view_as(participant)
    expect(response.parsed_body.at_css('.booking-details .status-label').text).to eq('Rescheduled')
    expect(response.parsed_body.at_css("a[href='#{program_booking_path(program, replacement)}']")).to be_present
    expect(response.body).to include('Travel')
    get program_booking_path(program, replacement)
    expect(response.parsed_body.at_css("a[href='#{program_booking_path(program, booking)}']")).to be_present
  end

  it 'does not link a participant to a replacement booked for someone else' do
    organizer = create_user
    grant_coordinator_access(program, organizer)
    other = create_user
    grant_participant_access(program, other)
    replacement = OrganizerBookingMutation.new(program: program, user: organizer).update(
      booking.id, date: booking.date.iso8601, user_id: other.id.to_s, attendance: 'unconfirmed',
                  reason: 'Swap', lock_version: booking.lock_version
    )
    track_booking(replacement)
    view_as(participant)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("a[href='#{program_booking_path(program, replacement)}']")).to be_nil
    view_as(organizer)
    expect(response.parsed_body.at_css("a[href='#{program_booking_path(program, replacement)}']")).to be_present
  end

  it 'links calendar and history entries to booking details' do
    view_as(participant)
    get calendar_program_path(program)
    day = response.parsed_body.at_css('td[data-date="2026-11-23"]')
    expect(day.css('a').pluck('href').uniq).to eq([program_booking_path(program, booking)])
    get history_program_path(program)
    expect(response.parsed_body.at_css("tr[data-booking='#{booking.id}'] a")['href'])
      .to eq(program_booking_path(program, booking))
    organizer = create_user
    grant_coordinator_access(program, organizer)
    sign_in(organizer)
    get calendar_program_path(program, month: '2026-11')
    links = response.parsed_body.at_css('td[data-date="2026-11-23"]').css('a').to_h { |link| [link.text, link['href']] }
    expect(links['View/Edit Booking']).to eq(program_booking_path(program, booking))
  end
end
