# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Participant details for coordinators', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(time_zone: 'America/New_York', start_time: '18:30', end_time: '21:00') }
  let(:participant) { create_user(name: 'Alex Model', display_name: nil) }
  let!(:booking) do
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-23'))
  end

  it 'shows coordinators contact details, access, notes, and linked bookings' do
    coordinator = create_user
    grant_coordinator_access(program, coordinator)
    membership = ProgramMembership.participants.where(program_id: program.id, user_id: participant.id).first
    membership.update!(notes: 'Prefers long poses')
    sign_in(coordinator)
    get participant_path(participant)
    page = response.parsed_body
    expect(page.at_css('h1').text).to eq('Alex Model')
    expect(response.body).to include(participant.email, participant.display_phone, 'Prefers long poses', 'Booked')
    expect(page.at_css("a[href='#{program_booking_path(program, booking)}']")).to be_present
    expect(page.at_css("a[href='#{edit_program_participant_path(program, membership)}']")).to be_present
  end

  it 'shows other participants and outsiders only the public profile' do
    other = create_user
    grant_participant_access(program, other)
    [other, create_user].each do |viewer|
      sign_in(viewer)
      get participant_path(participant)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css('h1').text).to eq('To be announced')
      expect(response.body).not_to include(participant.email, participant.display_phone, 'Booking Access')
    end
  end
end
