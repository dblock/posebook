# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cursor navigation', :aggregate_failures, :database, type: :system do
  let(:admin) { create_user(name: 'Studio Coordinator', roles: ['system_admin']) }
  let(:program) { create_program(name: 'Drawing Mondays', participant_label: 'Model') }
  let(:invitations) do
    Array.new(3) do |index|
      create_participant_invitation(program, admin, name: "Invited Model #{index}",
                                                    created_at: Time.utc(2026, 11, 14))
    end
  end

  before do
    stub_const('CursorPage::PER_PAGE', 2)
    invitations
    sign_in_through_browser(admin)
  end

  it 'keeps Previous and Next usable at every viewport without numbered pages' do
    each_viewport do |viewport|
      visit program_participant_invitations_path(program)
      expect(page).to have_css('tbody tr', count: 2)
      within('.participant-pagination') { click_on 'Next' }
      expect(page).to have_css('tbody tr', count: 1)
      expect(page).to have_text('Invited Model 0')
      expect(page).to have_no_link('Next')
      expect_no_horizontal_overflow
      capture_screenshot("cursor-invitations-#{viewport}")
      within('.participant-pagination') { click_on 'Previous' }
      expect(page).to have_css('tbody tr', count: 2)
      expect(page).to have_no_link('Previous')
      within('.participant-pagination') { click_on 'First' }
      expect(page).to have_css('tbody tr', count: 2)
    end
  end

  it 'resumes after an insertion and retains its cursor after revocation without JavaScript' do
    without_javascript do
      resize_to(:narrow)
      visit program_participant_invitations_path(program)
      create_participant_invitation(program, admin, name: 'New Model')
      within('.participant-pagination') { click_on 'Next' }
      expect(page).to have_css('tbody tr', count: 1)
      expect(page).to have_text('Invited Model 0')
      click_on 'Revoke'
      expect(page).to have_css('tbody tr', count: 1)
      expect(page).to have_text('Revoked')
      within('.participant-pagination') { click_on 'First' }
      expect(page).to have_text('New Model')
      expect_no_horizontal_overflow
    end
  end
end
