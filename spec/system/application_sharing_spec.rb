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

  it 'labels the link Closed after intake is turned off and hides it from participants' do
    visit edit_program_path(program)
    expect(page).to have_text('Requires email delivery and an active coordinator.')
    uncheck 'Accept Participation Applications'
    click_on 'Save Program'
    expect(sharing).to have_text('Closed')
    expect(sharing).to have_link(apply_url)

    participant = create_user(name: 'Riley Participant')
    grant_participant_access(program, participant)
    click_on 'Sign Out'
    sign_in_through_browser(participant)
    visit program_path(program)
    expect(page).to have_no_css('#application-sharing')
  end
end
