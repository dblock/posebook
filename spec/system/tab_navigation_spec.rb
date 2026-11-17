# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Grouped tab navigation', :aggregate_failures, :database, type: :system do
  let(:admin) { create_user(name: 'Studio Admin', roles: ['system_admin']) }
  let(:program) { create_program(name: 'Figure Drawing Mondays', participant_label: 'Model') }

  before do
    admin
    grant_participant_access(program, create_user(name: 'Studio Model'))
    sign_in_through_browser(admin)
  end

  it 'navigates program groups and highlights both levels at every viewport' do
    each_viewport do |viewport|
      visit program_path(program)
      { 'Models' => 'Invitations', 'Calendar' => 'Schedule Exceptions', 'Settings' => 'Coordinators' }
        .each do |primary, secondary|
        within('.program-tabs') { click_on primary }
        within('.program-secondary-tabs') { click_on secondary }
        expect(page).to have_css('.program-tabs [aria-current="page"]', text: primary)
        expect(page).to have_css('.program-secondary-tabs [aria-current="page"]', text: secondary)
        expect_no_horizontal_overflow
        capture_screenshot("program-#{primary.downcase}-#{viewport}")
      end
      within('.program-secondary-tabs') { click_on 'Google Calendar' }
      expect(page).to have_css('.program-secondary-tabs [aria-current="page"]', text: 'Google Calendar')
      within('.program-tabs') { click_on 'Photos' }
      expect(page).to have_css('.program-tabs [aria-current="page"]', text: 'Photos')
      expect(page).to have_no_css('.program-secondary-tabs')
    end
  end

  it 'puts venue creation and coordinator invitation beside their page headings at every viewport' do
    each_viewport do |viewport|
      visit venue_path(program.venue)
      within('.venue-tabs') { click_on 'Programs' }
      expect(page).to have_css('.title-row a.button-link', text: 'New Program')
      expect_no_horizontal_overflow
      capture_screenshot("venue-programs-#{viewport}")
      within('.venue-tabs') { click_on 'Settings' }
      within('.venue-secondary-tabs') { click_on 'Coordinators' }
      expect(page).to have_css('.venue-tabs [aria-current="page"]', text: 'Settings')
      expect(page).to have_css('.venue-secondary-tabs [aria-current="page"]', text: 'Coordinators')
      expect(page).to have_css('.title-row a.button-link', text: 'Invite a Coordinator')
      expect_no_horizontal_overflow
      capture_screenshot("venue-settings-#{viewport}")
    end
  end

  it 'keeps grouped navigation and contextual creation links working without JavaScript' do
    without_javascript do
      visit program_path(program)
      within('.program-tabs') { click_on 'Models' }
      within('.program-secondary-tabs') { click_on 'Invitations' }
      expect(page).to have_css('.program-tabs [aria-current="page"]', text: 'Models')
      within('.program-tabs') { click_on 'Settings' }
      within('.program-secondary-tabs') { click_on 'Coordinators' }
      click_on 'Invite a Coordinator'
      expect(page).to have_css('.program-secondary-tabs [aria-current="page"]', text: 'Coordinators')
      expect(page).to have_button('Continue')
      visit programs_venue_path(program.venue)
      click_on 'New Program'
      expect(page).to have_css('.venue-tabs [aria-current="page"]', text: 'Programs')
      expect(page).to have_button('Create Program')
    end
  end
end
