# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Administrator history navigation', :aggregate_failures, :database, type: :system do
  let(:admin) { create_user(name: 'Avery Administrator', roles: ['system_admin']) }
  let(:participant) { create_user(name: 'Jordan Model') }
  let(:entry) { participant.history_tracks.last }

  before do
    participant
    Current.set(user: admin) { participant.update!(name: 'Jordan Updated') }
    sign_in_through_browser(admin)
  end

  def open_change
    within("[data-history='#{entry.id}']") do
      find('summary').click
      expect(page).to have_text('Before: Jordan Model')
      expect(page).to have_text('After: Jordan Updated')
    end
  end

  it 'shows linked before and after values through the admin History tab at every viewport' do
    each_viewport do |viewport|
      visit admin_users_path
      within('.user-tabs') { click_on 'History' }
      expect(page).to have_css('.user-tabs [aria-current="page"]', text: 'History')
      open_change
      expect_no_horizontal_overflow
      capture_screenshot("admin-history-#{viewport}")
    end
    within("[data-history='#{entry.id}']") { click_on 'Jordan Updated' }
    expect(page).to have_current_path(admin_user_path(participant))
    expect(page).to have_css('h1', text: 'Profile')
    within('header') { click_on 'History' }
    expect(page).to have_current_path(admin_history_path)
  end

  it 'supports cursor navigation and change disclosure without JavaScript' do
    stub_const('CursorPage::PER_PAGE', 1)
    without_javascript do
      resize_to(:narrow)
      visit admin_history_path
      open_change
      within('.participant-pagination') { click_on 'Next' }
      expect(page).to have_link('First', href: admin_history_path)
      within('.participant-pagination') { click_on 'Previous' }
      expect(page).to have_css("[data-history='#{entry.id}']")
      within('.participant-pagination') { click_on 'First' }
      expect(page).to have_current_path(admin_history_path)
      expect_no_horizontal_overflow
    end
  end
end
