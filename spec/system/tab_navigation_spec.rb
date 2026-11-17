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

  it 'puts venue creation and coordinator invitations below their lists at every viewport' do
    each_viewport do |viewport|
      visit venue_path(program.venue)
      within('.venue-tabs') { click_on 'Programs' }
      expect(page).to have_css('.location-cards ~ p:last-child a.button-link', text: 'New Program')
      expect_no_horizontal_overflow
      capture_screenshot("venue-programs-#{viewport}")
      within('.venue-tabs') { click_on 'Settings' }
      within('.venue-secondary-tabs') { click_on 'Coordinators' }
      expect(page).to have_css('.venue-tabs [aria-current="page"]', text: 'Settings')
      expect(page).to have_css('.venue-secondary-tabs [aria-current="page"]', text: 'Coordinators')
      expect(page).to have_css('main > .coordinator-invitation-action:last-child a', text: 'Invite a Coordinator')
      expect_no_horizontal_overflow
      capture_screenshot("venue-settings-#{viewport}")
    end
  end

  it 'leaves spacing above invitation actions after populated program and venue coordinator lists' do
    coordinator = create_user(name: 'Assigned Coordinator')
    grant_venue_access(program.venue, coordinator)
    grant_coordinator_access(program, coordinator)
    each_viewport do |viewport|
      [program_coordinators_path(program), venue_coordinators_path(program.venue)].each_with_index do |path, index|
        visit path
        expect(page).to have_css('.coordinator-list', text: coordinator.name)
        action = find('main > .coordinator-invitation-action:last-child')
        expect(action).to have_link('Invite a Coordinator')
        expect(action.style('margin-block-start')).to eq('margin-block-start' => '24px')
        expect(page).to have_no_text('inherit access to every')
        expect_no_horizontal_overflow
        capture_screenshot("coordinator-invitation-#{index}-#{viewport}")
      end
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

  it 'keeps New Program at the bottom of an empty venue list without JavaScript' do
    venue = create_venue
    without_javascript do
      visit programs_venue_path(venue)
      expect(page).to have_text('No programs yet.')
      expect(page).to have_css('main > p:last-child a.button-link', text: 'New Program')
      click_on 'New Program'
      expect(page).to have_current_path(new_venue_program_path(venue))
      expect(page).to have_button('Create Program')
    end
  end
end
