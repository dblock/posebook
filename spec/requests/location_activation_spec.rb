# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Venue and program activation', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:venue) { program.venue }
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:coordinator) { create_user }
  let(:participant) { create_user }

  def book_participant
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
  end

  def expect_coordinator_cannot_activate_venue
    grant_venue_access(venue, coordinator)
    sign_in(coordinator)
    get edit_venue_path(venue)
    expect(response.body).not_to include('Deactivate Venue', 'Security')
    expect_venue_activation_forbidden
  end

  def expect_venue_activation_forbidden
    get security_venue_path(venue)
    expect(response).to have_http_status(:forbidden)
    patch venue_path(venue), params: { active: false }
    expect(response).to have_http_status(:forbidden)
  end

  def expect_program_coordinator_cannot_activate_program
    grant_coordinator_access(program, coordinator)
    sign_in(coordinator)
    get program_path(program)
    expect(response.parsed_body.css('.program-tabs a').map(&:text)).not_to include('Security')
    expect_program_activation_forbidden
  end

  def expect_program_activation_forbidden
    get security_program_path(program)
    expect(response).to have_http_status(:forbidden)
    patch program_path(program), params: { active: false }
    expect(response).to have_http_status(:forbidden)
  end

  it 'reserves venue activation for system admins and audits the actor' do
    expect_coordinator_cannot_activate_venue
    expect(venue.reload).to be_active
    sign_in(admin)
    get edit_venue_path(venue)
    expect(response.body).not_to include('Deactivate Venue')
    get security_venue_path(venue)
    expect(response.parsed_body.at_css('.venue-tabs [aria-current="page"]').text).to eq('Security')
    expect(response.body).to include('Deactivate Venue')
    patch venue_path(venue), params: { active: false }
    expect(response).to redirect_to(security_venue_path(venue))
    expect(venue.reload).not_to be_active
    expect(venue.history_tracks.last).to have_attributes(modified: { 'active' => false }, modifier_id: admin.id)
    patch venue_path(venue), params: { active: true }
    expect(venue.reload).to be_active
  end

  it 'allows venue coordinators but not program coordinators to change program activation' do
    expect_program_coordinator_cannot_activate_program
    grant_venue_access(venue, coordinator)
    patch program_path(program), params: { active: false }
    expect(response).to redirect_to(security_program_path(program))
    follow_redirect!
    expect(response.parsed_body.at_css('.program-tabs [aria-current="page"]').text).to eq('Security')
    expect(response.body).to include('Activate Program')
    get edit_program_path(program)
    expect(response.body).not_to include('Activate Program')
    expect(program.reload).not_to be_active
    expect(program.history_tracks.last).to have_attributes(modified: { 'active' => false },
                                                           modifier_id: coordinator.id)
    patch program_path(program), params: { active: true }
    expect(program.reload).to be_active
  end

  it 'rejects malformed state values and cannot change another venue or grant activation through settings' do
    grant_venue_access(venue, coordinator)
    sign_in(coordinator)
    [nil, '', '0', 'invalid', []].each do |value|
      patch program_path(program), params: { active: value }
      expect(response).to have_http_status(:bad_request)
      expect(program.reload).to be_active
    end
    other = create_program
    patch program_path(other), params: { active: false }
    expect(response).to have_http_status(:not_found)
    patch program_path(program), params: { program: { active: false, name: program.name } }
    expect(program.reload).to be_active
  end

  it 'hides inactive programs from public pages, listings, and direct photo reads' do
    program.update!(active: false)
    program_photo = track_record(ProgramPhoto.create!(program: program))
    get programs_venue_path(venue)
    expect(response.body).not_to include(program.name)
    [program_path(program), photos_program_path(program), program_photo_path(program, program_photo)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    venue.update!(active: false)
    photo = track_record(VenuePhoto.create!(venue: venue))
    [venue_path(venue), programs_venue_path(venue), photos_venue_path(venue),
     venue_photo_path(venue, photo)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'keeps inactive listings for booked participants but not unbooked invitees' do
    book_participant
    other = create_user
    grant_participant_access(program, other)
    venue.update!(active: false)
    sign_in(other)
    get program_path(program)
    expect(response).to have_http_status(:not_found)
    get venues_path
    expect(response.body).not_to include(venue.name)
    sign_in(participant)
    get venues_path
    expect(response.body).to include(venue.name, 'Inactive')
    get program_path(program)
    expect(response.body).to include('Your Upcoming Booking', 'Inactive')
    expect(response.body).not_to include('Reschedule')
  end

  it 'keeps inactive venues and programs available to their program managers' do
    venue.update!(active: false)
    grant_coordinator_access(program, coordinator)
    sign_in(coordinator)
    get venue_path(venue)
    expect(response).to have_http_status(:ok)
    get programs_venue_path(venue)
    expect(response.body).to include(program.name, 'Inactive')
    get edit_program_path(program)
    expect(response.body).to include('The venue is inactive.')
  end

  it 'retains confirmation, cancellation and private history without reopening bookings' do
    booking = book_participant
    program.update!(active: false)
    sign_in(participant)
    post confirm_program_booking_path(program, booking), params: { booking_version: booking.lock_version }
    expect(response).to redirect_to(profile_path)
    expect(booking.reload).to be_attendance_confirmed
    post cancel_program_booking_path(program, booking),
         params: { booking_version: booking.lock_version, reason: 'Existing booking cancellation.' }
    expect(response).to redirect_to(profile_path)
    expect(booking.reload.status).to eq('canceled')
    get history_profile_path
    expect(response.body).to include('Existing booking cancellation.')
    post program_bookings_path(program), params: { date: '2026-11-23' }
    expect(response).to redirect_to(profile_path)
  end

  it 'forces a full calendar refresh when venue activation changes during navigation' do
    book_participant
    sign_in(participant)
    get program_path(program, section: 'calendar')
    context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    expect(context).to be_present
    venue.update!(active: false)
    get program_path(program, section: 'calendar'), headers: { 'X-Posebook-Calendar-Context' => context }
    expect(response.parsed_body.at_css('main')).to be_present
    expect(response.body).to include('Inactive')
  end
end
