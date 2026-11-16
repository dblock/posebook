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
    click_on 'Sign Out'
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
