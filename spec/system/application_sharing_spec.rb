# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Application sharing', :aggregate_failures, :database, type: :system do
  let(:coordinator) { create_user(name: 'Jordan Coordinator') }
  let(:program) { create_program(name: "Figure Drawing Mondays at Enoch's", applications_enabled: true) }
  let(:sharing) { find_by_id('application-sharing') }
  let(:apply_url) { "#{page.server_url}#{program_apply_path(program)}" }

  before do
    grant_coordinator_access(program, coordinator)
    sign_in_through_browser(coordinator)
  end

  it 'configures a message prompt in settings and shows it in the application editor' do
    visit edit_program_path(program)
    fill_in 'Application Message Placeholder', with: 'Do you have any experience?'
    click_on 'Save Program'
    expect(page).to have_css('.flash', text: 'settings saved.')
    sign_out_through_browser
    sign_in_through_browser(create_user(email_verified_at: Time.current))
    each_viewport do |viewport|
      without_javascript do
        visit new_program_participation_application_path(program)
        expect(page).to have_field('Message (Optional)', placeholder: 'Do you have any experience?', with: '')
        expect_no_horizontal_overflow
        capture_screenshot("application-message-prompt-#{viewport}")
      end
    end
  end

  it 'cancels unsaved and saved applications without JavaScript or submitting them' do
    sign_out_through_browser
    applicant = create_user(email_verified_at: Time.current)
    sign_in_through_browser(applicant)
    without_javascript do
      visit new_program_participation_application_path(program)
      fill_in 'Phone', with: ''
      click_on 'Cancel Application'
      expect(page).to have_current_path(applications_profile_path)
      expect(ParticipantApplication.where(user_id: applicant.id)).not_to exist
      visit new_program_participation_application_path(program)
      fill_in 'Message (Optional)', with: 'Draft message'
      click_on 'Save Draft'
      expect(page).to have_css('.flash', text: 'Draft saved.')
      click_on 'Cancel Application'
      expect(page).to have_current_path(applications_profile_path)
      expect(ParticipantApplication.where(user_id: applicant.id)).not_to exist
    end
  end

  it 'requires consent to enable submission while keeping draft saving available' do
    sign_out_through_browser
    applicant = create_user(email_verified_at: Time.current)
    sign_in_through_browser(applicant)
    visit new_program_participation_application_path(program)
    expect(page).to have_button('Submit Application', disabled: true)
    find('[data-application-consent]').check
    expect(page).to have_button('Submit Application', disabled: false)
    find('[data-application-consent]').uncheck
    expect(page).to have_button('Submit Application', disabled: true)
    click_on 'Save Draft'
    expect(page).to have_css('.flash', text: 'Draft saved.')
    expect(page).to have_button('Submit Application', disabled: true)
    expect(ParticipantApplication.find_by(user_id: applicant.id).status).to eq('draft')
  end

  it 'saves drafts in place and then navigates after final submission' do
    sign_out_through_browser
    sign_in_through_browser(create_user(email_verified_at: Time.current))
    visit new_program_participation_application_path(program)
    mark_page
    fill_in 'Message (Optional)', with: 'My application'
    click_on 'Save Draft'
    expect(page).to have_css('.flash', text: 'Draft saved.')
    expect_unchanged_page
    click_on 'Save Draft'
    expect(page).to have_button('Save Draft', disabled: false)
    find('[data-application-consent]').check
    click_on 'Submit Application'
    expect(page).to have_current_path(applications_profile_path)
  end

  it 'shows a visible application link beside Copy Link at every viewport' do
    each_viewport do |viewport|
      visit program_path(program, token: 'private')
      expect(sharing).to have_text('Open')
      expect(sharing).to have_link(apply_url, href: apply_url)
      expect(sharing).to have_button('Copy Link')
      expect_no_horizontal_overflow
      capture_screenshot("application-sharing-#{viewport}")
    end

    participant = create_user(name: 'Riley Participant')
    grant_participant_access(program, participant)
    sign_out_through_browser
    sign_in_through_browser(participant)
    visit program_path(program)
    expect(page).to have_no_css('#application-sharing')
  end

  it 'copies the canonical link and keeps it visible when copying fails' do
    visit program_path(program, token: 'private')
    stub_clipboard
    sharing.click_on('Copy Link')
    expect(sharing).to have_button('Copied')
    expect(copied_text).to eq(apply_url)

    stub_clipboard(failure: true)
    sharing.click_on('Copied')
    expect(sharing).to have_text('Could not copy. Select the text and copy it manually.')
    expect(sharing).to have_link(apply_url)
  end

  it 'keeps the link usable without JavaScript' do
    without_javascript do
      resize_to(:narrow)
      visit program_path(program)
      expect(sharing).to have_link(apply_url, count: 1)
      expect(sharing).to have_no_button('Copy Link')
      expect_no_horizontal_overflow
    end
  end

  it 'keeps closed links clickable and shows a helpful landing page at every viewport' do
    visit edit_program_path(program)
    expect(page).to have_text('Requires email and an active coordinator.')
    uncheck 'Accept Participation Applications'
    click_on 'Save Program'
    expect(page).to have_css('.flash', text: 'saved')
    each_viewport do |viewport|
      visit program_path(program)
      expect(sharing).to have_text('Closed')
      expect(sharing).to have_link(apply_url, href: apply_url)
      sharing.click_link(apply_url)
      expect(page).to have_css('h1', text: 'Applications Closed')
      expect(page).to have_text('not currently accepting applications')
      expect(page).to have_link('View Program', href: program_path(program))
      expect_no_horizontal_overflow
      capture_screenshot("application-closed-landing-#{viewport}")
    end
  end

  it 'keeps closed URLs copyable and usable without JavaScript' do
    program.update!(applications_enabled: false)
    visit program_path(program)
    stub_clipboard
    sharing.click_on('Copy Link')
    expect(sharing).to have_button('Copied')
    expect(copied_text).to eq(apply_url)

    without_javascript do
      visit program_path(program)
      expect(sharing).to have_text(apply_url)
      expect(sharing).to have_link(apply_url, href: apply_url)
      expect(sharing).to have_no_button('Copy Link')
      sharing.click_link(apply_url)
      expect(page).to have_css('h1', text: 'Applications Closed')
      click_on 'View Program'
      expect(page).to have_current_path(program_path(program))
    end
  end

  it 'keeps the application URL clickable when the program or venue is inactive' do
    [program, program.venue].each do |location|
      location.update!(active: false)
      visit program_path(program)
      expect(sharing).to have_text('Closed')
      expect(sharing).to have_link(apply_url, href: apply_url)
      location.update!(active: true)
    end
  end
end
