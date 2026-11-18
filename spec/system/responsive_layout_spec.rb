# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Responsive layout', :aggregate_failures, :database, type: :system do
  include ActiveSupport::Testing::TimeHelpers

  # Two-digit afternoon clocks produce the widest compact date labels.
  around { |example| travel_to(Time.utc(2026, 11, 18, 22, 58)) { example.run } }

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
              program: program_path(program), calendar: calendar_program_path(program),
              history: history_program_path(program), participants: program_participants_path(program),
              invitations: program_participant_invitations_path(program),
              applications: program_applications_path(program), edit: edit_program_path(program),
              profile: profile_path, bookings: bookings_profile_path }
    each_viewport do |viewport|
      pages.each do |name, path|
        visit path
        expect(page).to have_css('main')
        expect_no_horizontal_overflow
        capture_screenshot("#{name}-#{viewport}")
      end
    end
  end

  it 'fits invitation columns on desktop and keeps narrow screens within the viewport' do
    create_participant_invitation(program, coordinator, name: 'Accepted Invitee With A Longer Name',
                                                        email: 'avery.accepted.long.address@example.test',
                                                        created_at: 4.days.ago, used_at: 3.days.ago)
    each_viewport do |viewport|
      visit program_participant_invitations_path(program)
      table = find('table.participant-invitations')
      expect(width_of(table)).to be <= width_of(find('.table-scroll')) if viewport == :desktop
      expect(table).to have_text('Accepted Invitee With A Longer Name')
      expect(table).to have_button('Revoke')
      expect_no_horizontal_overflow
      capture_screenshot("compact-invitations-#{viewport}")
    end
  end
end
