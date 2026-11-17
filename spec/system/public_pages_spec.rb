# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public pages', :aggregate_failures, :database, type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:program) { create_program(name: 'Public Drawing Mondays') }

  before { create_user }

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  def open_participant_home
    participant = create_user(name: 'Studio Model')
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
    sign_in_through_browser(participant)
    visit root_path
  end

  it 'shows upcoming sessions, venue programs, and the embedded calendar at every viewport' do
    program
    pages = { 'public-home' => root_path, 'public-venue' => venue_path(program.venue),
              'public-program' => program_path(program) }
    each_viewport do |viewport|
      pages.each do |name, path|
        visit path
        expect(page).to have_no_css('.page-tabs')
        expect(page).to have_link('Sign In', href: new_session_path)
        expect(page).to have_css(name == 'public-program' ? '[data-calendar]' : '.upcoming-sessions')
        expect(page).to have_css('.next-session + .venue-card', text: program.venue.name) if name == 'public-program'
        expect_no_horizontal_overflow
        capture_screenshot("#{name}-#{viewport}")
      end
    end
  end

  it 'keeps the public program and calendar usable without JavaScript' do
    program
    without_javascript do
      visit root_path
      click_on program.name, match: :first
      expect(page).to have_css('.next-session')
      expect(page).to have_no_css('.next-session dt')
      within('.next-session + .venue-card') do
        click_on program.venue.name
      end
      expect(page).to have_current_path(venue_path(program.venue))
      visit program_path(program)
      expect(page).to have_css('[data-calendar]')
      expect(page).to have_no_link('View Calendar')
      click_on 'Next Month'
      expect(page).to have_css('[data-calendar]')
    end
  end

  it 'keeps application preparation as wide as the public program at every viewport' do
    program.update!(applications_enabled: true)
    each_viewport do |viewport|
      visit program_path(program)
      width = width_of(page.find('main'))
      visit new_program_application_registration_path(program)
      expect(page).to have_field('Email')
      expect(width_of(page.find('main'))).to eq(width)
      expect(width_of(page.find_field('Email'))).to be < width if viewport == :desktop
      expect_no_horizontal_overflow
      capture_screenshot("application-preparation-#{viewport}")
    end
  end

  it 'shows managed programs instead of public sessions on the coordinator homepage' do
    coordinator = create_user(name: 'Studio Coordinator')
    grant_coordinator_access(program, coordinator)
    sign_in_through_browser(coordinator)
    visit root_path
    expect(page).to have_css('h1', text: 'Posebook')
    expect(page).to have_css('h2', text: 'Programs You Manage')
    expect(page).to have_link(program.name, href: program_path(program))
    expect(page).to have_no_css('.upcoming-sessions')
    each_viewport do |viewport|
      expect_no_horizontal_overflow
      capture_screenshot("management-home-#{viewport}")
    end
  end

  it 'shows participants their own upcoming booking and their programs at every viewport' do
    open_participant_home
    expect(page).to have_css('.upcoming-booking', count: 1)
    expect(page).to have_css('.upcoming-booking-photo figcaption', text: 'Booked')
    expect(page).to have_css('.participant-programs', text: program.name)
    expect(page).to have_no_css('.upcoming-sessions')
    each_viewport do |viewport|
      expect_no_horizontal_overflow
      capture_screenshot("participant-home-#{viewport}")
    end
  end

  it 'confirms attendance from the same action group as cancellation without duplicate prompts' do
    open_participant_home
    expect(page).to have_no_css('.booking-attendance .attendance-warning')
    expect(page).to have_css('.rescheduling-notice', text: 'Attendance Confirmation Needed')
    within('.booking-actions') do
      expect(page).to have_link('Cancel Booking')
      click_on "I'll be there!"
    end
    expect(page).to have_css('.upcoming-booking .status-label', text: 'Confirmed')
    visit root_path
    expect(page).to have_css('.upcoming-booking-photo figcaption', text: 'Confirmed')
    expect(page).to have_no_css('.rescheduling-notice', text: 'Attendance Confirmation Needed')
    capture_screenshot('participant-attendance-confirmed')
  end

  it 'links a participant calendar booking to its upcoming booking card' do
    open_participant_home
    visit program_path(program, section: 'calendar')
    find('.calendar a', text: 'Booked').click
    expect(page).to have_current_path(program_path(program), ignore_query: true)
    expect(page).to have_css('.upcoming-booking')
    expect(URI.parse(page.current_url).fragment).to start_with('upcoming-booking-')
  end
end
