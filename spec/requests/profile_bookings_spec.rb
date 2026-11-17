# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Profile bookings', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:participant) { create_user }
  let(:other) { create_user }
  let(:booked) { create_program }
  let(:available) { create_program }
  let(:restricted) { { paused: create_program, exhausted: create_program } }

  def paused
    restricted.fetch(:paused)
  end

  def exhausted
    restricted.fetch(:exhausted)
  end

  before do
    [booked, available, paused, exhausted].each { |program| grant_participant_access(program, participant) }
    grant_participant_access(booked, other)
    track_booking(BookingMutation.new(program: booked, user: participant).book(date: '2026-12-07'))
    track_booking(BookingMutation.new(program: booked, user: other).book(date: '2026-12-14'))
    track_booking(BookingMutation.new(program: exhausted, user: participant).book(date: '2026-11-16'))
    paused.memberships.participants.find_by(user_id: participant.id)
          .update!(participant_paused: true, participant_pause_reason: 'Manager-only pause reason.')
    travel_to Time.utc(2026, 11, 24, 15)
    sign_in(participant)
  end

  it 'lists your current bookings and only programs with an unused active booking invitation' do
    get bookings_profile_path
    expect(response.parsed_body.at_css('.upcoming-booking').text).to include('Mon, Dec 7', booked.name)
    expect(response.parsed_body.css('.bookable-programs .program-card h2 a').map(&:text)).to eq([available.name])
    expect(response.parsed_body.at_css(".bookable-programs a[href='#{program_path(available,
                                                                                  section: 'calendar')}']"))
      .to be_present
    expect(response.body).not_to include(other.email, 'December 14, 2026', 'Manager-only pause reason.')
    expect(response.parsed_body.css('.nav-links a').map(&:text)).to eq(%w[Profile Venues])
    expect(response.parsed_body.at_css(".nav-account[href='#{profile_path}']")).to be_present
  end

  it 'shows your retained all-program history without exposing other models or accepting a user ID' do
    booking = booked.bookings.find_by(user_id: participant.id)
    BookingMutation.new(program: booked, user: participant).cancel(booking: booking, reason: 'Travel plans changed.')
    get history_profile_path(user_id: other.id)
    expect(response.body).to include(booked.name, exhausted.name, 'Canceled', 'Completed', 'Travel plans changed.')
    expect(response.body).not_to include(other.email, '2026-12-14', 'Manager-only pause reason.')
    expect(response.parsed_body.at_css('.profile-tabs [aria-current="page"]').text).to eq('History')
    expect(response.parsed_body.at_css('.breadcrumbs [aria-current="page"]').text).to eq('History')
    expect(response.parsed_body.css('tbody tr[data-booking]').size).to eq(2)
  end

  it 'retains owner history after membership loss without offering new bookings there' do
    available.memberships.participants.find_by(user_id: participant.id).set(roles: [])
    exhausted.memberships.participants.find_by(user_id: participant.id).set(roles: [])
    [bookings_profile_path, root_path].each do |path|
      get path
      expect(response.parsed_body.css('.bookable-programs .program-card')).to be_empty
    end
    get history_profile_path
    expect(response.body).to include(exhausted.name, 'Completed')
    delete session_path
    get history_profile_path
    expect(response).to redirect_to(new_session_path)
  end

  it 'preserves live booking access decisions for legacy invitation timestamps' do
    programs = [booked, available, paused, exhausted]
    members = programs.map { |program| program.memberships.participants.find_by(user_id: participant.id) }
    members.each { |member| member.set(booking_invited_at: nil) }
    dashboard = ParticipantDashboard.new(participant)
    members.each do |member|
      expect(dashboard.access_for(member.program_id).allowed?).to eq(BookingAccess.new(member).allowed?)
    end
  end

  it 'paginates private owner history without hiding older bookings or accepting another user ID' do
    stub_const('ParticipantHistory::PER_PAGE', 1)
    get history_profile_path(user_id: other.id)
    expect(response.parsed_body.css('tbody tr').size).to eq(1)
    expect(response.parsed_body.at_css('main p').text).to end_with('of 2 bookings')
    next_path = response.parsed_body.at_css('a[rel="next"]')['href']
    expect(next_path).to start_with("#{history_profile_path}?cursor=")
    get next_path, params: { user_id: other.id }
    expect(response.body).to include(exhausted.name, 'Completed')
    expect(response.body).not_to include('2026-12-14', other.email)
    previous_path = response.parsed_body.at_css('a[rel="prev"]')['href']
    expect(response.parsed_body.at_css('.participant-pagination a').text).to eq('First')
    expect(response.parsed_body.at_css('a[rel="next"]')).to be_nil
    get previous_path
    expect(response.body).to include(booked.name)
    expect(response.parsed_body.at_css('a[rel="prev"]')).to be_nil
    get history_profile_path(cursor: 'invalid', page: 999)
    expect(response.body).to include(booked.name)
  end
end
