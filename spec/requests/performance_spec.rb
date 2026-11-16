# frozen_string_literal: true

require 'rails_helper'
require_relative '../../script/benchmark_user_experience'

RSpec.describe 'User experience read performance', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:participant) { create_user(gender: 'female') }

  def commands
    monitor = UserExperienceBenchmark::Commands.new
    Mongoid.default_client.subscribe(Mongo::Monitoring::COMMAND, monitor)
    yield
    monitor.result
  ensure
    Mongoid.default_client.unsubscribe(Mongo::Monitoring::COMMAND, monitor) if monitor
  end

  it 'keeps dashboard database work bounded as the number of eligible programs grows' do
    allow(ParticipantDashboard).to receive(:new).and_call_original
    programs = Array.new(12) { create_program }
    programs.each { |program| grant_participant_access(program, participant) }
    track_booking(BookingMutation.new(program: programs.first, user: participant).book(date: '2026-11-16'))
    sign_in(participant)
    result = commands { get bookings_profile_path }
    expect(response.parsed_body.css('.bookable-programs .program-card').size).to eq(11)
    expect(response.parsed_body.css('.upcoming-booking').size).to eq(1)
    expect(result[:commands]).to be <= 25
    expect(result[:collections]['bookings']).to eq(3)
    expect(result[:collections]['users']).to eq(1)
    expect(ParticipantDashboard).to have_received(:new).with(participant).once
  end

  it 'batch loads managed programs, parent venues, and fallback photos on the programs tab' do
    programs = Array.new(12) { create_program }
    programs.each { |program| grant_coordinator_access(program, participant) }
    sign_in(participant)
    result = commands { get programs_profile_path }
    expect(response.parsed_body.css('.managed-programs .program-card').size).to eq(12)
    expect(result[:commands]).to be <= 25
    expect(result[:collections]['users']).to eq(1)
  end

  it 'reuses calendar absence snapshots but still checks neighbors outside the displayed date range' do
    program = create_program(available_weekdays: %w[0 1 2 3 4 5 6], no_consecutive_genders: ['female'])
    grant_participant_access(program, participant)
    neighbor = create_user(gender: 'female')
    grant_participant_access(program, neighbor)
    track_booking(BookingMutation.new(program: program, user: neighbor).book(date: '2026-11-28'))
    sign_in(participant)
    result = commands { get program_path(program, section: 'calendar', month: '2026-12') }
    expect(response.parsed_body.at_css('[data-date="2026-11-29"]')['class']).to eq('blocked')
    expect(response.parsed_body.at_css('[data-date="2026-12-02"]')['class']).to eq('available')
    expect(result[:collections]['bookings']).to be <= 8
    expect(response.body).not_to include(neighbor.email)
  end

  it 'batch loads only owned primary photos and retains fallback, explicit galleries and reload behavior' do
    venues = Array.new(4) { create_venue }
    first = venues.first(3).map { |venue| VenuePhoto.create!(venue: venue) }
    selected = VenuePhoto.create!(venue: venues.first, created_at: Time.current + 1)
    venues.first.update!(primary_photo_id: selected.id)
    venues[1].update!(primary_photo_id: selected.id)
    venues[2].update!(primary_photo_id: BSON::ObjectId.new)
    result = commands { Venue.preload_primary_photos(venues) }
    expect(venues.map { |venue| venue.primary_photo&.id }).to eq([selected.id, first[1].id, first[2].id, nil])
    expect(result[:collections]['venue_photos']).to be <= 3
    expect(venues.first.primary_photo([first.first])).to eq(first.first)
    selected.destroy!
    expect(venues.first.reload.primary_photo).to eq(first.first)
  end

  it 'keeps organizer contact snapshots active, program-scoped and fresh between requests' do
    program = create_program
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
    active = create_user
    inactive = create_user(active: false)
    foreign = create_user
    [active, inactive].each { |user| grant_coordinator_access(program, user) }
    grant_coordinator_access(create_program, foreign)
    sign_in(participant)
    get bookings_profile_path
    expect(response.body).to include(active.email)
    expect(response.body).not_to include(inactive.email, foreign.email)
    grant_coordinator_access(program, foreign)
    get bookings_profile_path
    expect(response.body).to include(foreign.email)
  end
end
