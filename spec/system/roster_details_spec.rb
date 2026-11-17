# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Roster details', :aggregate_failures, :database, type: :system do
  let(:coordinator) { create_user(name: 'Roster Coordinator') }
  let(:participant) { create_user(name: 'Roster Model', email: 'long.model.email.address@example.test') }
  let(:program) { create_program(applications_enabled: true, participant_label: 'Model') }
  let(:membership) { grant_participant_access(program, participant) }

  before do
    grant_venue_access(program.venue, coordinator)
    grant_coordinator_access(program, coordinator)
    sign_in_through_browser(coordinator)
  end

  def expect_expanded_note(member)
    row = find("#pause-note-#{member.id}")
    expect(row.all('td').map { |cell| cell[:colspan] }).to eq(%w[3 3])
    expect(row).to have_css('td:last-child', text: member.participant_pause_reason)
  end

  def toggle_pause_note(member, viewport)
    selector = "#pause-note-#{member.id}"
    expect(page).to have_no_css(selector)
    toggle = find("summary[aria-controls='pause-note-#{member.id}']")
    toggle_note(toggle, selector) do
      expect_expanded_note(member)
      expect_no_horizontal_overflow
      capture_screenshot("roster-expanded-note-#{viewport}")
    end
  end

  def toggle_note(toggle, selector)
    expect_pause_arrow(toggle)
    border = note_border_color(toggle)
    toggle.click
    yield
    expect(note_border_color(toggle)).not_to eq(border)
    toggle.send_keys(:enter)
    expect(page).to have_no_css(selector)
  end

  def expect_pause_arrow(toggle)
    size = toggle.style('font-size').fetch('font-size').to_f
    arrow_size = toggle.find('span').style('font-size').fetch('font-size').to_f
    expect(arrow_size).to eq(size * 2)
  end

  def note_border_color(toggle)
    toggle.find(:xpath, 'ancestor::td').style('border-bottom-color').fetch('border-bottom-color')
  end

  def withdrawn_application
    user = create_user(email_verified_at: Time.current)
    workflow = ParticipantApplicationWorkflow.new(program: program, user: user)
    application = track_record(workflow.submit(message: nil, consent: '1'))
    workflow.withdraw(application.id, version: application.lock_version)
    application
  end

  def rejected_event
    participant.update!(email_verified_at: Time.current)
    application = track_record(ParticipantApplicationWorkflow.new(program: program, user: participant)
                                                              .submit(message: nil, consent: '1'))
    ParticipantApplicationWorkflow.new(program: program, user: coordinator)
                                  .review(application.id, status: 'declined', version: application.lock_version,
                                                          notes: 'Private reviewer explanation.')
    application.events.last
  end

  def toggle_history_note(event, viewport)
    selector = "#event-notes-#{event.id}"
    expect(page).to have_no_css(selector)
    toggle = find("summary[aria-controls='event-notes-#{event.id}']")
    toggle_note(toggle, selector) do
      expect(page).to have_css("#{selector} .participant-notes", text: event.notes)
      expect_no_horizontal_overflow
      capture_screenshot("history-expanded-note-#{viewport}")
    end
  end

  def table_font_size(path, viewport)
    visit path
    expect(width_of(find('.table-scroll .participant-identity', match: :first))).to be >= 352
    expect_no_horizontal_overflow
    capture_screenshot("table-type-#{path.split('/').last}-#{viewport}")
    find('.table-scroll tbody td', match: :first).style('font-size').fetch('font-size')
  end

  it 'opens pause notes across the rightmost three columns at every viewport' do
    membership.update!(participant_paused: true, participant_pause_reason: 'Taking a break until December.')
    each_viewport do |viewport|
      visit program_participants_path(program)
      toggle_pause_note(membership, viewport)
      expect(page).to have_css('main > form:last-child button', text: 'Invite All Available Models (0)')
      expect(find('.participant-bulk-invite').style('margin-block-start')).to eq('margin-block-start' => '16px')
    end
  end

  it 'filters counted roster statuses in place with browser Back navigation' do
    membership.update!(participant_paused: true, participant_pause_reason: 'Taking a break.')
    available = create_user(name: 'Available Model')
    grant_participant_access(program, available)
    visit program_participants_path(program)
    mark_page
    select 'Paused (1)', from: 'Status'
    expect(page).to have_current_path(program_participants_path(program, status: 'paused'))
    expect(page).to have_css('tr[data-membership]', count: 1, text: participant.email)
    select 'Available (1)', from: 'Status'
    expect(page).to have_current_path(program_participants_path(program, status: 'available'))
    expect(page).to have_css('tr[data-membership]', count: 1, text: available.email)
    page.go_back
    expect(page).to have_select('Status', selected: 'Paused (1)')
    expect(page).to have_css('tr[data-membership]', count: 1, text: participant.email)
    expect_unchanged_page
  end

  it 'filters event history in place with plain event text and profile links for actors' do
    application = withdrawn_application
    visit history_program_applications_path(program)
    mark_page
    select 'Application Withdrawn', from: 'Event'
    expect(page).to have_css('.participation-history tbody tr', count: 1)
    expect(page).to have_css('.participation-history td:nth-child(3)', text: 'Application Withdrawn')
    expect(page).to have_link(application.name, href: participant_path(application.user_id))
    select 'Application Submitted', from: 'Event'
    expect(page).to have_css('.participation-history td:nth-child(3)', text: 'Application Submitted')
    expect(page).to have_current_path(history_program_applications_path(program, event: 'application_submitted'))
    expect_unchanged_page
  end

  it 'filters event history without JavaScript' do
    withdrawn_application
    without_javascript do
      visit history_program_applications_path(program)
      select 'Application Withdrawn', from: 'Event'
      click_on 'Filter'
      expect(page).to have_css('.participation-history tbody tr', count: 1)
      expect(page).to have_css('.participation-history td:nth-child(3)', text: 'Application Withdrawn')
    end
  end

  it 'expands history notes with the roster arrow at every viewport' do
    event = rejected_event
    each_viewport do |viewport|
      visit history_program_applications_path(program)
      expect(page).to have_css('tr[data-event] .participant-note-toggle', count: 1)
      expect(page).to have_css('.participation-history td:nth-child(3)', text: 'Application: Not Now')
      expect(page).to have_no_css('.participation-history .status-label')
      toggle_history_note(event, viewport)
    end
  end

  it 'expands history notes without JavaScript' do
    event = rejected_event
    without_javascript do
      visit history_program_applications_path(program)
      expect(page).to have_css('tr[data-event] .participant-note-toggle', count: 1)
      toggle_history_note(event, :no_javascript)
    end
  end

  it 'filters invitation statuses and revokes a pending invitation from its detail page' do
    invitation = create_participant_invitation(program, coordinator, name: 'Pending Model')
    create_participant_invitation(program, coordinator, name: 'Old Model', revoked_at: Time.current)
    visit program_participant_invitations_path(program)
    mark_page
    select 'Pending', from: 'Status'
    expect(page).to have_css('tr[data-invitation]', count: 1, text: invitation.name)
    expect_unchanged_page
    within('tbody') { click_on 'View' }
    click_on 'Revoke'
    expect(page).to have_select('Status', selected: 'Pending')
    expect(page).to have_no_css('tr[data-invitation]')
    select 'Revoked', from: 'Status'
    expect(page).to have_css('tr[data-invitation]', count: 2)
    expect(invitation.reload.status).to eq('Revoked')
  end

  it 'opens and closes pause notes without JavaScript and keeps invitation controls below the table' do
    membership.update!(participant_paused: true, participant_pause_reason: 'Private pause explanation.')
    without_javascript do
      visit program_participants_path(program)
      toggle_pause_note(membership, :no_javascript)
      expect(page).to have_button('Invite All Available Models (0)', disabled: true)
    end
  end

  it 'uses the invitation table font size for rosters, applications, and coordinators at every viewport' do
    membership
    create_participant_invitation(program, coordinator, name: 'Invited Model')
    applicant = create_user(email_verified_at: Time.current)
    track_record(ParticipantApplicationWorkflow.new(program: program, user: applicant).submit(message: nil,
                                                                                              consent: '1'))
    paths = [program_participant_invitations_path(program), program_participants_path(program),
             program_applications_path(program), program_coordinators_path(program)]
    each_viewport do |viewport|
      sizes = paths.map { |path| table_font_size(path, viewport) }
      expect(sizes.uniq.size).to eq(1)
    end
  end

  it 'opens Applications History from the participant group and selects its History tab' do
    visit program_applications_path(program)
    within('.program-secondary-tabs') { click_on 'History' }
    expect(page).to have_current_path(history_program_applications_path(program))
    expect(page).to have_css('h1', text: 'Applications History')
    expect(page).to have_css('.program-secondary-tabs [aria-current="page"]', text: 'History')
    expect(page).to have_css('.program-tabs [aria-current="page"]', text: 'Models')
  end
end
