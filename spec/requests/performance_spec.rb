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

  it 'batch loads public preview IDs without mixing owners, exposing private photos, or changing primary order' do
    venues = Array.new(4) { create_venue }
    photos = venues.map do |venue|
      public_photos = Array.new(2) { track_record(VenuePhoto.create!(venue: venue)) }
      track_record(VenuePhoto.create!(venue: venue, public: false))
      venue.update!(primary_photo_id: public_photos.last.id)
      public_photos.reverse
    end
    sign_in(create_user(roles: ['system_admin']))
    result = commands { get venues_path }
    venues.zip(photos).each do |venue, series|
      card = response.parsed_body.at_css(".venue-card a[href='#{venue_path(venue)}']").ancestors('.venue-card').first
      expect(card.css('[data-photo-preview]').pluck('href')).to eq(series.map { |photo|
        venue_photo_path(venue, photo)
      })
    end
    expect(result[:collections]['venue_photos']).to be <= 2
  end

  it 'batch loads fallback venue series even when programs have no photos of their own' do
    venue = create_venue
    photo = track_record(VenuePhoto.create!(venue: venue))
    programs = Array.new(4) { create_program(venue: venue) }
    ids = nil
    result = commands do
      Program.preload_primary_photos(programs, series: true)
      ids = programs.map { |program| program.venue.public_photo_ids }
    end
    expect(ids).to all(eq([photo.id]))
    expect(result[:collections]['venue_photos']).to be <= 3
  end

  it 'refreshes preview IDs on owner reload and after a primary preference changes' do
    venue = create_venue
    photo = track_record(VenuePhoto.create!(venue: venue))
    Venue.preload_primary_photos([venue], series: true)
    next_photo = track_record(VenuePhoto.create!(venue: venue))
    venue.primary_photo_id = photo.id
    expect(venue.public_photo_ids).to eq([photo.id, next_photo.id])
    photo.update!(public: false)
    expect(venue.reload.public_photo_ids).to eq([next_photo.id])
  end

  it 'batch loads only booked participant display overrides across public programs' do
    programs = Array.new(10) { create_program }
    programs.each_with_index do |program, index|
      grant_participant_access(program, participant).update!(display_name_override: "Program Model #{index}")
      track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
    end
    result = commands { get root_path }
    expect(response.body).to include('Program Model 0', 'Program Model 9')
    expect(result[:collections]['program_memberships']).to eq(1)
  end

  it 'batch loads schedule exceptions while preserving scoped closures, overnight openings and fresh requests' do
    create_user
    programs = Array.new(10) { create_program }
    closure = track_record(ProgramScheduleException.create!(program: programs.first, date: '2026-11-16',
                                                            mode: 'closed', reason: 'Closed.'))
    track_record(ProgramScheduleException.create!(program: programs.last, date: '2026-11-17', mode: 'open',
                                                  start_time: '23:00', end_time: '01:00', reason: 'Extra session.'))
    result = commands { get root_path }
    rows = response.parsed_body.css('.upcoming-sessions tbody tr')
    opening = rows.find { |row| row.text.include?(programs.last.name) && row.text.include?('Tue, Nov 17') }
    expect(rows.find { |row| row.text.include?(programs.first.name) }.text).to include('Mon, Nov 23')
    expect(opening.text).to include('11:00 PM', 'next day')
    expect(result[:collections]['program_schedule_exceptions']).to eq(1)
    closure.update!(mode: 'regular')
    get root_path
    first = response.parsed_body.css('.upcoming-sessions tbody tr')
                    .find { |row| row.text.include?(programs.first.name) }
    expect(first.text).to include('Mon, Nov 16')
  end

  it 'retains the local calendar window and later exceptions across a server month boundary' do
    program = create_program(time_zone: 'America/New_York')
    %w[2026-11-16 2026-12-07].each do |date|
      track_record(ProgramScheduleException.create!(program: program, date: date, mode: 'closed', reason: 'Closed.'))
    end
    travel_to Time.utc(2026, 12, 1, 1)
    calendar = UpcomingSessions.new(Program.where(id: program.id)).first.calendar
    expect(calendar.schedule.exceptions.keys).to contain_exactly(Date.new(2026, 11, 16), Date.new(2026, 12, 7))
    expect(calendar.session_on?(Date.new(2026, 12, 7))).to be(false)
  end

  it 'reads binary photo chunks in order across cursor batches without repeated counts' do
    payload = "\x00\xffbinary".b * 1152
    file = track_record(ProfilePhoto.storage.file_model.create!(filename: 'photo.webp', chunkSize: 1024,
                                                                length: payload.bytesize))
    9.times do |index|
      file.chunks.create!(n: index, data: BSON::Binary.new(payload.byteslice(index * 1024, 1024)))
    end
    photo = ProfilePhoto.new(image_id: file.id)
    result = commands { expect(photo.bytes).to eq(payload) }
    expect(result[:collections]['photos.files']).to eq(1)
    expect(result[:collections]['photos.chunks']).to eq(2)
  end

  it 'retains inactive participant programs only when booked or managed and refreshes visibility' do
    program = create_program(name: 'Public Mondays')
    grant_participant_access(program, participant)
    booked = create_program(name: 'Booked Mondays')
    grant_participant_access(booked, participant)
    track_booking(BookingMutation.new(program: booked, user: participant).book(date: '2026-11-16'))
    booked.update!(active: false)
    managed = create_program(name: 'Managed Mondays', active: false)
    grant_participant_access(managed, participant)
    grant_coordinator_access(managed, participant)
    grant_participant_access(create_program(name: 'Hidden Mondays', active: false), participant)
    expect(ParticipantDashboard.new(participant).participating_programs.map(&:name))
      .to eq(['Booked Mondays', 'Managed Mondays', 'Public Mondays'])
    program.update!(active: false)
    expect(ParticipantDashboard.new(participant).participating_programs.map(&:name))
      .to eq(['Booked Mondays', 'Managed Mondays'])
  end

  it 'reuses loaded participant program venues instead of reading them again for homepage cards' do
    Array.new(10) { create_program }.each { |program| grant_participant_access(program, participant) }
    sign_in(participant)
    result = commands { get root_path }
    expect(response.parsed_body.css('.participant-programs h2 a').size).to eq(10)
    expect(result[:collections]['venues']).to be <= 5
  end
end
