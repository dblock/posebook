# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Management table filters', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:program) { create_program }
  let(:manager) { create_user }

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  before do
    grant_coordinator_access(program, manager)
    sign_in(manager)
  end

  def roster_members
    entries = %i[available booked paused inactive].index_with do |status|
      grant_participant_access(program, create_user(active: status != :inactive))
    end
    entries[:paused].update!(participant_paused: true, participant_pause_reason: 'Taking a break.')
    user = entries[:booked].user
    track_booking(BookingMutation.new(program: program, user: user).book(date: '2026-11-16'))
    entries
  end

  def invitation_states
    past = 1.day.ago
    future = 1.day.from_now
    { pending: { expires_at: future },
      accepted: { used_at: past, revoked_at: past, expires_at: past },
      revoked: { revoked_at: past, expires_at: past },
      expired: { expires_at: past } }.transform_values do |attributes|
      create_participant_invitation(program, manager, **attributes)
    end
  end

  def review_events
    user = create_user
    source = track_record(ParticipantApplication.create!(program: program, user: user, profile_shared_at: Time.current))
    invitation = create_participant_invitation(program, manager)
    ParticipationEvent::REVIEW_ACTIONS.map do |action|
      track_record(ParticipationEvent.create!(program: program, user: user, actor: manager, action: action,
                                              source_id: action == 'invitation_accepted' ? invitation.id : source.id))
    end
  end

  %w[all available booked paused inactive].each do |status|
    it "filters the roster to #{status} without changing program-wide counts" do
      entries = roster_members
      expected = status == 'all' ? entries.values : [entries.fetch(status.to_sym)]
      get program_participants_path(program, status: status)
      expect(response.parsed_body.css('tr[data-membership]').pluck('data-membership'))
        .to eq(expected.map { |member| member.id.to_s })
      expect(response.parsed_body.css('select option').map(&:text))
        .to eq(['All Participants (4)', 'Available (1)', 'Booked (1)', 'Paused (1)', 'Inactive (1)'])
      expect(response.body).not_to include('Showing 4 of 4', 'total participants')
    end
  end

  %w[all pending accepted revoked expired].each do |status|
    it "filters invitations to #{status}, preserving terminal-state precedence and program scope" do
      entries = invitation_states
      create_participant_invitation(create_program, manager)
      expected = status == 'all' ? entries.values.reverse : [entries.fetch(status.to_sym)]
      get program_participant_invitations_path(program, status: status)
      expect(response.parsed_body.css('tr[data-invitation]').pluck('data-invitation'))
        .to eq(expected.map { |invitation| invitation.id.to_s })
    end
  end

  ParticipationEvent::REVIEW_ACTIONS.each do |action|
    it "filters application history to #{action} with linked actors and plain event text" do
      event = review_events.find { |entry| entry.action == action }
      get history_program_applications_path(program, event: action)
      expect(response.parsed_body.css('tr[data-event]').pluck('data-event')).to eq([event.id.to_s])
      expect(response.parsed_body.at_css('tbody .status-label')).to be_nil
      expect(response.parsed_body.at_css('tbody td:nth-child(5) a')['href']).to eq(participant_path(manager))
    end
  end

  it 'rejects invalid filters and private draft event types' do
    { program_participants_path(program) => { status: 'pending' },
      program_participant_invitations_path(program) => { status: 'draft' },
      history_program_applications_path(program) => { event: 'application_reopened' } }.each do |path, query|
      get path, params: query
      expect(response).to have_http_status(:bad_request)
    end
  end

  it 'preserves invitation filters after a pending invitation is revoked from its detail page' do
    invitation = invitation_states.fetch(:pending)
    get program_participant_invitation_path(program, invitation, status: 'pending')
    form = response.parsed_body.at_css('main form.button_to')
    expect(form.at_css('button').text).to eq('Revoke')
    delete form['action']
    expect(response).to redirect_to(program_participant_invitations_path(program, status: 'pending'))
    expect(invitation.reload.status).to eq('Revoked')
    follow_redirect!
    expect(response.parsed_body.at_css('tr[data-invitation]')).to be_nil
  end

  it 'preserves history event filters across cursor pages' do
    stub_const('CursorPage::PER_PAGE', 1)
    event = review_events.first
    track_record(ParticipationEvent.create!(program: program, user: event.user, actor: manager,
                                            source_id: event.source_id, action: event.action))
    get history_program_applications_path(program, event: event.action)
    next_path = response.parsed_body.at_css('a[rel="next"]')['href']
    expect(next_path).to include("event=#{event.action}")
    get next_path
    expect(response.parsed_body.css('tr[data-event]').pluck('data-event')).to eq([event.id.to_s])
    get next_path.sub(event.action, 'application_declined')
    expect(response.parsed_body.css('tbody tr').size).to eq(1)
    expect(response.parsed_body.at_css('tbody td:nth-child(3)').text).to eq('Application Rejected')
  end
end
