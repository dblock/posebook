# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notification settings', :aggregate_failures, :database, type: :system do
  let(:organizer) { create_user }
  let(:program) { create_program(time_zone: 'America/New_York', start_time: '18:30', end_time: '21:00') }

  before do
    grant_coordinator_access(program, organizer)
    sign_in_through_browser(organizer)
  end

  it 'edits mandatory admin templates with safe live previews at every width' do
    sign_out_through_browser
    sign_in_through_browser(create_user(roles: ['system_admin']))
    visit admin_settings_notifications_path
    check_layouts('admin-list')
    find_link('Edit', href: edit_admin_settings_notification_path('password_reset')).click
    expect(page).not_to have_field('Enabled')
    fill_in 'Subject', with: 'Security for {recipient_name}'
    expect(page).to have_css('[data-preview-subject]', text: 'Security for Alex Example')
    expect(ActionMailer::Base.deliveries).to be_empty
    check_layouts('admin-editor')
  end

  it 'edits venue defaults and displays inherited reminder timing in program settings' do
    grant_venue_access(program.venue, organizer)
    visit edit_venue_notification_path(program.venue, 'application_draft')
    fill_in 'Elapsed Days After First Save or Reopening', with: '3'
    check_layouts('venue-editor')
    click_on 'Save Notification'
    expect(page).to have_css('[role="status"]', text: 'Notification saved.')
    visit edit_program_notification_path(program, 'application_draft')
    expect(page).to have_field('Elapsed Days After First Save or Reopening', with: '3')
  end

  it 'saves personal preferences without JavaScript' do
    without_javascript do
      visit notifications_profile_path
      check_layouts('personal-preferences')
      uncheck 'Incomplete Application Reminders'
      uncheck 'Coordinator Alerts'
      click_on 'Save Preferences'
      expect(page).to have_css('[role="status"]', text: 'Notification saved.')
      expect(organizer.reload).to have_attributes(application_reminders_enabled: false,
                                                  coordinator_notifications_enabled: false)
    end
  end

  it 'lists purposes, opens the selected editor, and reflects saved notification status' do
    visit program_notifications_path(program)
    expect(page).to have_css('table', text: 'Purpose')
    expect(page).not_to have_field('Subject')
    check_layouts('list')
    find_link('Edit', href: edit_program_notification_path(program, 'confirmation_request')).click
    expect(page).to have_current_path(edit_program_notification_path(program, 'confirmation_request'))
    uncheck 'Enabled'
    click_on 'Save Notification'
    click_on 'Cancel'
    within('tr', text: 'Attendance Confirmation Request') { expect(page).to have_text('Disabled') }
  end

  it 'previews edits and placeholders without saving and keeps the editor usable at every width' do
    visit edit_program_notification_path(program, 'confirmation_request')
    expect(page).to have_select('Confirmation Opens', selected: 'At Previous Session End')
    expect(page).to have_css('[data-days-timing]', visible: :hidden)
    fill_in 'Subject', with: 'Session for {participant_name}'
    fill_in 'Message', with: 'Custom text for {program_name}'
    expect(page).to have_css('[data-preview-subject]', text: 'Session for Alex Example')
    expect(page).to have_css('[data-preview-body]', text: "Custom text for #{program.name}")
    expect(program.reload.notification_settings).to be_empty
    select 'Days Before the Session', from: 'Confirmation Opens'
    fill_in 'Calendar Days Before', with: '6'
    expect(page).to have_field('Time', with: '12:00')
    click_on '{booking_url}'
    expect(find_field('Message').value).to include('{booking_url}')
    check_layouts('editor')
    click_on 'Save Notification'
    expect(page).to have_css('[role="status"]', text: 'Notification saved.')
    expect(BookingNotificationSetting.for(program.reload, 'confirmation_request').days_before).to eq(6)
  end

  def check_layouts(context)
    each_viewport do |viewport|
      expect_no_horizontal_overflow
      capture_screenshot("booking-notifications-#{context}-#{viewport}")
    end
  end

  it 'inserts clickable placeholders at the selection in the last focused field' do
    visit edit_program_notification_path(program, 'booking_created')
    fill_in 'Subject', with: 'Hello NAME'
    page.execute_script("document.getElementById('notification_subject').setSelectionRange(6, 10)")
    click_on '{participant_name}'
    expect(page).to have_field('Subject', with: 'Hello {participant_name}')
    fill_in 'Message', with: 'Hello NAME'
    page.execute_script("document.getElementById('notification_body').setSelectionRange(6, 10)")
    click_on '{program_name}'
    expect(page).to have_field('Message', with: 'Hello {program_name}')
    expect(page).to have_css('[data-preview-body]', text: "Hello #{program.name}")
    expect(program.reload.notification_settings).to be_empty
  end

  it 'cancels unsaved edits and resets cleared templates without JavaScript' do
    without_javascript do
      visit edit_program_notification_path(program, 'booking_created')
      fill_in 'Subject', with: 'Discard this edit'
      click_on 'Cancel'
      expect(page).to have_current_path(program_notifications_path(program))
      expect(program.reload.notification_settings).to be_empty
      find_link('Edit', href: edit_program_notification_path(program, 'booking_created')).click
      expect(page).to have_field('Subject', with: /You're booked/)
      fill_in 'Subject', with: ''
      fill_in 'Message', with: ''
      click_on 'Save Notification'
      expect(page).to have_field('Subject', with: /You're booked/)
      expect(BookingNotificationSetting.for(program.reload, 'booking_created').subject).to be_nil
    end
  end
end
