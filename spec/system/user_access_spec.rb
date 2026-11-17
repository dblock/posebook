# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'User access', :aggregate_failures, :database, type: :system do
  let(:admin) { create_user(name: 'Avery Admin', roles: ['system_admin']) }
  let!(:member) { create_user(name: 'Morgan Member') }
  let(:row) { find_by_id("user_#{member.id}") }

  before { sign_in_through_browser(admin) }

  it 'fits desktop account tables and keeps narrow pages contained' do
    member.update!(name: 'Morgan Member With A Longer Account Name')
    each_viewport do |viewport|
      visit admin_users_path
      expect(width_of(find('.user-accounts'))).to be <= width_of(find('.table-scroll')) if viewport == :desktop
      expect_no_horizontal_overflow
      capture_screenshot("compact-user-accounts-#{viewport}")
    end
  end

  it 'deactivates and reactivates a user without reloading the page' do
    visit admin_users_path
    mark_page

    row.click_on('Deactivate')
    expect(row).to have_text('Inactive')
    expect(row).to have_button('Reactivate')
    expect(page).to have_css('.flash', text: 'Account access updated.', count: 1)
    capture_screenshot('user-access-flash')
    expect(member.reload).not_to be_active

    row.click_on('Reactivate')
    expect(row).to have_button('Deactivate')
    expect(page).to have_css('.flash', count: 1)
    expect(member.reload).to be_active
    expect_unchanged_page

    find('button[aria-label="Dismiss"]').click
    expect(page).to have_no_css('.flash')
  end

  it 'reloads the page without JavaScript' do
    without_javascript do
      visit admin_users_path
      row.click_on('Deactivate')
      expect(row).to have_button('Reactivate')
      expect(member.reload).not_to be_active
    end
  end
end
