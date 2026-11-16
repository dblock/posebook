# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Homepage', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(name: 'Public Mondays') }

  def session_rows
    response.parsed_body.css('.upcoming-sessions tbody tr').map { |row| row.css('td').map { |cell| cell.text.squish } }
  end

  it 'lists upcoming public sessions for guests' do
    participant = create_user(name: 'Private Name', display_name: 'Booked Model')
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
    create_program(name: 'Hidden Program', active: false)
    create_program(name: 'Hidden Venue', venue: create_venue(active: false))
    get root_path
    expect(response).to have_http_status(:ok)
    expect(session_rows.map { |row| row.values_at(0, 2, 3) })
      .to eq([['Mon, Nov 16', 'Public Mondays', program.venue.name],
              ['Mon, Nov 23', 'Public Mondays', program.venue.name]])
    expect(session_rows.map(&:last)).to eq(['Booked Model', 'To be announced'])
    expect(response.body).not_to include('Hidden Program', 'Hidden Venue', 'Private Name')
    expect(response.parsed_body.at_css('.site-nav a.button-link')['href']).to eq(new_session_path)
  end

  it 'shows participants their own upcoming booking instead of the public session list' do
    participant = create_user
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
    sign_in(participant)
    get root_path
    expect(response.parsed_body.css('.upcoming-booking').size).to eq(1)
    expect(response.parsed_body.at_css('.upcoming-booking-photo figcaption .status-label').text).to eq('Booked')
    expect(response.parsed_body.at_css('.rescheduling-notice').text).to include('Please confirm that you will be there')
    expect(response.parsed_body.at_css('.upcoming-booking').text.scan('Please confirm that you will be there').size)
      .to eq(1)
    expect(response.body).to include('Your Upcoming Booking', "Welcome, #{participant.name}.", 'View Your Profile')
    expect(response.parsed_body.at_css('.upcoming-sessions, .site-nav a.button-link')).to be_nil
  end

  it 'lists every viewable participant program without granting paused access or showing unassigned programs' do
    participant = create_user
    grant_participant_access(program, participant)
    paused = create_program(name: 'Paused Mondays')
    grant_participant_access(paused, participant).update!(participant_paused: true,
                                                          participant_pause_reason: 'Unavailable.')
    create_program(name: 'Unassigned Mondays')
    sign_in(participant)
    get root_path
    cards = response.parsed_body.css('.participant-programs .program-card')
    expect(cards.css('h2 a').map(&:text)).to eq(['Paused Mondays', 'Public Mondays'])
    expect(cards.css('.button-link').pluck('href')).to eq([program_path(program, section: 'calendar')])
    expect(response.body).not_to include('Unassigned Mondays')
  end

  it 'applies per-program participant privacy overrides' do
    participant = create_user(name: 'Real Name', instagram_handle: 'real_model')
    membership = grant_participant_access(program, participant)
    membership.update!(display_name_override: 'Stage Name', instagram_hidden: true)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
    get root_path
    expect(session_rows.first.last).to eq('Stage Name')
    expect(response.body).not_to include('Real Name', 'real_model')
  end

  it 'lists only the venue programs and sessions on its public page' do
    create_program(name: 'Elsewhere Mondays')
    create_program(name: 'Paused Mondays', venue: program.venue, active: false)
    get venue_path(program.venue)
    expect(response.parsed_body.css('.program-card h2 a').map(&:text)).to eq(['Public Mondays'])
    expect(session_rows.map(&:first)).to eq(['Mon, Nov 16', 'Mon, Nov 23'])
    expect(session_rows.pluck(2).uniq).to eq(['Public Mondays'])
    expect(response.parsed_body.at_css('.upcoming-sessions').text).not_to include('Venue')
  end

  it 'explains when nothing is scheduled' do
    create_user
    get root_path
    expect(response.body).to include('No sessions in the next two weeks.')
  end

  it 'shows coordinators only their directly assigned and inherited programs, including inactive programs' do
    coordinator = create_user
    grant_coordinator_access(program, coordinator)
    inherited = create_program(name: 'Inherited Mondays', active: false)
    grant_venue_access(inherited.venue, coordinator)
    foreign = create_program(name: 'Unassigned Mondays')
    sign_in(coordinator)
    get root_path
    expect(response.parsed_body.css('.managed-programs h2 a').map(&:text))
      .to eq(['Inherited Mondays', 'Public Mondays'])
    expect(response.body).to include('Programs You Manage')
    expect(response.body).to include('You have coordinator access.', 'View Your Profile', 'View Venues')
    expect(response.body).not_to include(foreign.name, 'Upcoming Sessions')
  end

  it 'shows administrators all programs on their homepage' do
    admin = create_user(roles: ['system_admin'])
    program
    create_program(name: 'Inactive Mondays', active: false)
    sign_in(admin)
    get root_path
    expect(response.parsed_body.css('.managed-programs h2 a').map(&:text))
      .to eq(['Inactive Mondays', 'Public Mondays'])
    expect(response.parsed_body.at_css('.upcoming-sessions')).to be_nil
    expect(response.body).to include('You have the system admin role.', 'View Your Profile', 'View Venues')
    expect(response.body).to include("Welcome, #{admin.name}.")
  end

  it 'keeps the management homepage for administrators and venue coordinators without programs' do
    admin = create_user(roles: ['system_admin'])
    coordinator = create_user
    grant_venue_access(create_venue, coordinator)
    [admin, coordinator].each do |user|
      sign_in(user)
      get root_path
      expect(response.body).to include('Programs You Manage', 'No programs to manage.')
      expect(response.body).not_to include('Upcoming Sessions')
    end
  end
end
