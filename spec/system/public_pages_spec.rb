# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public pages', :aggregate_failures, :database, type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:program) { create_program(name: 'Public Drawing Mondays') }

  before { create_user }

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  def open_participant_home(date: '2026-11-16')
    participant = create_user(name: 'Studio Model')
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: date))
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

  def application_listing_path(listing)
    listing == :home ? root_path : program_applications_path(program)
  end

  def expect_filtered_applicant(applicant)
    expect(page).to have_select('Status', selected: 'Withdrawn')
    expect(page).to have_css('[data-application-region] tbody', text: applicant.email)
    expect(page).to have_current_path(/status=withdrawn/)
    expect_unchanged_page
  end

  def expect_empty_applications
    expect(page).to have_text('No applications in this view.')
    expect(page).to have_current_path(/status=accepted/)
    expect(page).to have_select('Status', selected: 'Accepted')
    expect_unchanged_page
  end

  it 'opens application review from a plain table link without JavaScript' do
    applicant, application = create_submitted_application
    sign_in_through_browser(create_user(roles: ['system_admin']))
    without_javascript do
      visit program_applications_path(program)
      capture_screenshot('application-review-link')
      find('td a:not(.button-link)', text: 'Review', exact_text: true).click
      expect(page).to have_current_path(program_application_path(program, application))
      expect(page).to have_css('h1', text: 'Review Application')
      capture_screenshot('application-history-actor-links')
      within('[aria-label="Application history"]') { click_on applicant.name }
      expect(page).to have_current_path(admin_user_path(applicant))
    end
  end

  it 'lets administrators open submitted applications from their homepage at every viewport' do
    applicant, application = create_withdrawn_application
    sign_in_through_browser(create_user(roles: ['system_admin']))
    each_viewport do |viewport|
      visit root_path
      expect(page).to have_select('Status', selected: 'Pending')
      expect(page).to have_text('No applications in this view.')
      select 'All', from: 'Status'
      within('.submitted-applications') do
        expect(page).to have_text(applicant.email)
        expect(page).to have_text('Withdrawn')
        expect_no_horizontal_overflow
        capture_screenshot("admin-submitted-applications-#{viewport}")
        find('a:not(.button-link)', text: 'View', exact_text: true).click
      end
      expect(page).to have_current_path(program_application_path(program, application))
      expect(page).to have_css('h1', text: 'Review Application')
    end
  end

  it 'labels declined reviews and links the applicant account at every viewport' do
    applicant, application = create_submitted_application
    sign_in_through_browser(create_user(roles: ['system_admin']))
    visit program_application_path(program, application)
    click_on 'Reject'
    expect(page).to have_current_path(program_applications_path(program))
    visit program_application_path(program, application)
    each_viewport do |viewport|
      expect(page).to have_css('main > p .status-label', text: 'Reject')
      expect(page).to have_link(applicant.name, href: participant_path(applicant))
      expect_no_horizontal_overflow
      capture_screenshot("declined-review-#{viewport}")
    end
    find('main > p a').click
    expect(page).to have_current_path(admin_user_path(applicant))
  end

  %i[home program].each do |listing|
    it "filters #{listing} applications in place with browser Back and Forward" do
      applicant, = create_withdrawn_application
      sign_in_through_browser(create_user(roles: ['system_admin']))
      visit application_listing_path(listing)
      mark_page
      select 'Withdrawn', from: 'Status'
      expect_filtered_applicant(applicant)
      expect(page).to have_no_button('Filter')
      select 'Accepted', from: 'Status'
      expect_empty_applications
      page.go_back
      expect_filtered_applicant(applicant)
      page.go_forward
      expect_empty_applications
    end

    it "filters #{listing} applications without JavaScript when there are no pending submissions" do
      applicant, = create_withdrawn_application
      sign_in_through_browser(create_user(roles: ['system_admin']))
      without_javascript do
        visit application_listing_path(listing)
        expect(page).to have_select('Status', selected: 'Pending')
        expect(page).to have_text('No applications in this view.')
        select 'Withdrawn', from: 'Status'
        click_on 'Filter'
        expect(page).to have_select('Status', selected: 'Withdrawn')
        expect(page).to have_css('[data-application-region] tbody', text: applicant.email)
      end
    end

    it "paginates #{listing} applications in place and resets the cursor when filtering" do
      stub_const('CursorPage::PER_PAGE', 2)
      applicants = Array.new(3) { create_withdrawn_application.first }
      sign_in_through_browser(create_user(roles: ['system_admin']))
      visit application_listing_path(listing)
      mark_page
      select 'Withdrawn', from: 'Status'
      expect(page).to have_css('[data-application-region] tbody tr', count: 2)
      click_on 'Next'
      expect(page).to have_css('[data-application-region] tbody tr', count: 1, text: applicants.first.email)
      select 'All', from: 'Status'
      expect(page).to have_current_path("#{application_listing_path(listing)}?status=all")
      expect(page).to have_css('[data-application-region] tbody tr', count: 2)
      expect_unchanged_page
    end
  end

  it 'views a withdrawn application read-only before reopening, editing, and submitting it with new consent' do
    applicant, application = create_withdrawn_application
    sign_in_through_browser(applicant)
    visit root_path
    within('.homepage-applications') { click_on 'View' }
    expect(page).to have_text('Original experience')
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
      expect(page).to have_current_path(calendar_program_path(program, month: '2026-12'))
      expect(page).to have_css('[data-calendar]')
    end
  end

  it 'opens the dedicated calendar page from the embedded overview calendar' do
    visit program_path(program)
    click_on 'Next Month'
    expect(page).to have_current_path(calendar_program_path(program, month: '2026-12'))
    expect(page).to have_css('[data-calendar-month]', text: 'December')
    expect(page).to have_no_css('.next-session')
  end

  it 'navigates dedicated calendar months in place with browser Back and Forward' do
    visit calendar_program_path(program)
    mark_page
    click_on 'Next Month'
    expect(page).to have_current_path(calendar_program_path(program, month: '2026-12'))
    expect(page).to have_css('[data-calendar-month]', text: 'December')
    page.go_back
    expect(page).to have_current_path(calendar_program_path(program))
    expect(page).to have_css('[data-calendar-month]', text: 'November')
    page.go_forward
    expect(page).to have_current_path(calendar_program_path(program, month: '2026-12'))
    expect(page).to have_css('[data-calendar-month]', text: 'December')
    expect_unchanged_page
  end

  it 'keeps rescheduling month navigation on the booking editor' do
    open_participant_home(date: '2026-11-23')
    click_on 'Reschedule'
    path = page.current_path
    mark_page
    click_on 'Next Month'
    expect(page).to have_current_path("#{path}?month=2026-12")
    expect(page).to have_css('h1', text: 'Change Your Booking Date')
    expect(page).to have_field('What changed?')
    expect_unchanged_page
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
    visit calendar_program_path(program)
    find('.calendar a', text: 'Booked').click
    expect(page).to have_current_path(program_path(program), ignore_query: true)
    expect(page).to have_css('.upcoming-booking')
    expect(URI.parse(page.current_url).fragment).to start_with('upcoming-booking-')
  end
end
