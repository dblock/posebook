# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Responsive layout', :aggregate_failures, :database, type: :system do
  let(:coordinator) { create_user(name: 'Jordan Coordinator With A Long Display Name') }
  let(:program) { create_program(name: 'Figure Drawing Mondays at the Long-Named Community Studio') }

  before do
    grant_coordinator_access(program, coordinator)
    grant_participant_access(program, create_user(name: 'Riley Participant', email: 'riley.long.address@example.test'))
    create_participant_invitation(program, coordinator, name: 'Avery Invitee', email: 'avery.invitee@example.test')
    sign_in_through_browser(coordinator)
  end

  it 'keeps coordinator pages within the viewport' do
    pages = { home: root_path, venues: venues_path, venue: venue_path(program.venue),
              program: program_path(program), calendar: program_path(program, section: 'calendar'),
              history: program_path(program, section: 'history'), participants: program_participants_path(program),
              invitations: program_participant_invitations_path(program),
              applications: program_applications_path(program), edit: edit_program_path(program),
              profile: profile_path, account: details_profile_path }
    each_viewport do |viewport|
      pages.each do |name, path|
        visit path
        expect(page).to have_css('main')
        expect_no_horizontal_overflow
        capture_screenshot("#{name}-#{viewport}")
      end
    end
  end
end
