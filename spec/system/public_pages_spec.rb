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

  def expect_application_table(viewport, name)
    expect(page).to have_css('table', text: program.name)
    expect(page).to have_button('Cancel Application')
    expect_no_horizontal_overflow
    capture_screenshot("#{name}-#{viewport}")
  end

  def create_submitted_application
    program.update!(applications_enabled: true)
    applicant = create_user(email_verified_at: Time.current)
    grant_coordinator_access(program, create_user)
    workflow = ParticipantApplicationWorkflow.new(program: program, user: applicant)
    application = track_record(workflow.submit(message: 'Original experience', consent: '1'))
    [applicant, application]
  end

  def create_withdrawn_application
    applicant, application = create_submitted_application
    ParticipantApplicationWorkflow.new(program: program, user: applicant)
                                  .withdraw(application.id, version: application.lock_version)
    [applicant, application]
  end

  it 'views a withdrawn application read-only before reopening, editing, and submitting it with new consent' do
    applicant, application = create_withdrawn_application
    sign_in_through_browser(applicant)
    visit root_path
    within('.homepage-applications') { click_on 'View' }
    expect(page).to have_text('Original experience')
    expect(find('.application-resubmit').style('margin-block-start')).to eq('margin-block-start' => '16px')
    expect(page).to have_no_css('main input:not([type="hidden"]), main select')
    visit applications_profile_path
    click_on 'Resubmit'
    expect(page).to have_field('Message (Optional)', with: 'Original experience')
    expect(page).to have_button('Submit Application', disabled: true)
    fill_in 'Message (Optional)', with: 'New experience'
    check "I agree to share my information with the program's coordinators."
    click_on 'Submit Application'
    expect(page).to have_current_path(applications_profile_path)
    expect(application.reload.message).to eq('New experience')
  end

  it 'shares the draft table between homepage and profile without JavaScript at every viewport' do
    program.update!(applications_enabled: true)
    applicant = create_user(email_verified_at: Time.current)
    track_record(ApplicationDraft.new(program: program, user: applicant).save(version: nil,
                                                                              message: 'My saved experience'))
    sign_in_through_browser(applicant)
    each_viewport do |viewport|
      without_javascript do
        visit root_path
        expect_application_table(viewport, 'continue-application')
        click_on 'Continue Application'
        expect(page).to have_field('Message (Optional)', with: 'My saved experience')
        visit applications_profile_path
        expect_application_table(viewport, 'profile-applications')
      end
    end
  end

  it 'cancels a draft from its homepage table without JavaScript' do
    program.update!(applications_enabled: true)
    applicant = create_user(email_verified_at: Time.current)
    application = track_record(ApplicationDraft.new(program: program, user: applicant).save(version: nil))
    sign_in_through_browser(applicant)
    without_javascript do
      visit root_path
      within('.homepage-applications tbody') { click_on 'Cancel Application' }
      expect(page).to have_current_path(applications_profile_path)
      visit root_path
      expect(page).to have_no_css('.homepage-applications')
      expect(ParticipantApplication.where(id: application.id)).not_to exist
    end
  end

  %i[root_path applications_profile_path].each do |listing|
    it "withdraws a submitted application from #{listing} without JavaScript" do
      program.update!(applications_enabled: true)
      applicant = create_user(email_verified_at: Time.current)
      application = track_record(ApplicationDraft.new(program: program, user: applicant).save(version: nil))
      application.update!(status: 'pending', profile_shared_at: Time.current)
      sign_in_through_browser(applicant)
      without_javascript do
        visit public_send(listing)
        click_on 'Withdraw'
        expect(page).to have_text('Status: Withdrawn')
        expect(application.reload.status).to eq('withdrawn')
        visit public_send(listing)
        expect(page).to have_css('table', text: 'Withdrawn')
        expect(page).to have_no_button('Withdraw')
      end
    end
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
