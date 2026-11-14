# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinator hierarchy', :aggregate_failures, :database, type: :request do
  let(:venue) { create_venue }
  let(:program) { create_drawing_session(venue: venue) }
  let(:other_program) { create_drawing_session }
  let(:coordinator) { create_user }

  it 'inherits every session at a coordinated venue without granting access elsewhere' do
    sibling = create_drawing_session(venue: venue)
    grant_venue_access(venue, coordinator)
    expect(DrawingSession.managed_by(coordinator)).to contain_exactly(program, sibling)
    expect(DrawingSession.visible_to(coordinator)).not_to include(other_program)
    sign_in(coordinator)
    patch venue_path(venue), params: { venue: { address: 'Updated coffee shop address.' } }
    expect(venue.reload.address).to eq('Updated coffee shop address.')
    patch drawing_session_path(program), params: { drawing_session: { instructions: 'New session instructions.' } }
    expect(program.reload.instructions).to eq('New session instructions.')
    get edit_drawing_session_path(other_program)
    expect(response).to have_http_status(:not_found)
  end

  it 'allows venue coordinators to create sessions only at their own venue' do
    grant_venue_access(venue, coordinator)
    sign_in(coordinator)
    post venue_drawing_sessions_path(venue),
         params: { drawing_session: { name: 'Tuesday Drawing', available_weekdays: ['2'] } }
    created = track_record(venue.drawing_sessions.find_by(name: 'Tuesday Drawing'))
    expect(response).to redirect_to(drawing_session_path(created))
    post venue_drawing_sessions_path(other_program.venue), params: { drawing_session: { name: 'Forbidden' } }
    expect(response).to have_http_status(:not_found)
    post venue_coordinators_path(venue), params: { email: coordinator.email }
    expect(response).to have_http_status(:forbidden)
    expect(coordinator.reload.roles).to be_empty
  end

  it 'lets venue coordinators delegate sessions without creating a global user directory' do
    grant_venue_access(venue, coordinator)
    assignee = create_user
    sign_in(coordinator)
    get drawing_session_coordinators_path(program)
    expect(response.body).not_to include(assignee.email)
    post drawing_session_coordinators_path(program), params: { email: assignee.email, roles: ['system_admin'] }
    membership = track_record(DrawingSessionMembership.find_by(drawing_session_id: program.id, user_id: assignee.id))
    expect(membership.roles).to eq(['session_coordinator'])
    expect(assignee.reload.roles).to be_empty
    post drawing_session_coordinators_path(other_program), params: { email: assignee.email }
    expect(response).to have_http_status(:forbidden)
  end

  it 'limits session coordinators to their own session and prevents parent or peer delegation' do
    grant_coordinator_access(program, coordinator)
    sibling = create_drawing_session(venue: venue)
    sign_in(coordinator)
    get edit_drawing_session_path(program)
    expect(response).to have_http_status(:ok)
    get edit_drawing_session_path(sibling)
    expect(response).to have_http_status(:not_found)
    get edit_venue_path(venue)
    expect(response).to have_http_status(:not_found)
    post drawing_session_coordinators_path(program), params: { email: coordinator.email }
    expect(response).to have_http_status(:forbidden)
  end

  it 'allows only admins to assign venue coordinators and revokes inherited access immediately' do
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    post venue_coordinators_path(venue), params: { email: coordinator.email }
    membership = track_record(VenueMembership.find_by(venue_id: venue.id, user_id: coordinator.id))
    expect(program.managed_by?(coordinator)).to be(true)
    delete venue_coordinator_path(venue, membership)
    expect(program.managed_by?(coordinator)).to be(false)
    expect(coordinator.reload.roles).to be_empty
  end

  it 'publishes location details and session links without private session information' do
    program
    get venue_path(venue)
    expect(response.body).to include(venue.name, venue.address, drawing_session_path(program))
    expect(response.body).not_to include('Model Pay', 'Booking History', 'Create Session', 'Session Coordinators')
    expect(response.parsed_body.css('[data-calendar], form')).to be_empty
  end
end
