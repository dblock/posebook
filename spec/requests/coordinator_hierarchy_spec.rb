# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinator hierarchy', :aggregate_failures, :database, type: :request do
  let(:venue) { create_venue }
  let(:program) { create_program(venue: venue) }
  let(:other_program) { create_program }
  let(:coordinator) { create_user }

  it 'inherits every session at a coordinated venue without granting access elsewhere' do
    sibling = create_program(venue: venue)
    grant_venue_access(venue, coordinator)
    expect(Program.managed_by(coordinator)).to contain_exactly(program, sibling)
    expect(Program.visible_to(coordinator)).not_to include(other_program)
    sign_in(coordinator)
    patch venue_path(venue), params: { venue: { address: 'Updated coffee shop address.' } }
    expect(venue.reload.address).to eq('Updated coffee shop address.')
    patch program_path(program), params: { program: { instructions: 'New session instructions.' } }
    expect(program.reload.instructions).to eq('New session instructions.')
    get edit_program_path(other_program)
    expect(response).to have_http_status(:not_found)
  end

  it 'allows venue coordinators to create sessions only at their own venue' do
    grant_venue_access(venue, coordinator)
    sign_in(coordinator)
    post venue_programs_path(venue),
         params: { program: { name: 'Tuesday Drawing', available_weekdays: ['2'] } }
    created = track_record(venue.programs.find_by(name: 'Tuesday Drawing'))
    expect(response).to redirect_to(program_path(created))
    post venue_programs_path(other_program.venue), params: { program: { name: 'Forbidden' } }
    expect(response).to have_http_status(:not_found)
    post venue_coordinators_path(venue), params: { email: coordinator.email }
    expect(response).to have_http_status(:forbidden)
    expect(coordinator.reload.roles).to be_empty
  end

  it 'lets venue coordinators delegate sessions without creating a global user directory' do
    grant_venue_access(venue, coordinator)
    assignee = create_user
    sign_in(coordinator)
    get program_coordinators_path(program)
    expect(response.body).not_to include(assignee.email)
    post program_coordinators_path(program), params: { email: assignee.email, roles: ['system_admin'] }
    membership = track_record(ProgramMembership.find_by(program_id: program.id, user_id: assignee.id))
    expect(membership.roles).to eq(['program_coordinator'])
    expect(assignee.reload.roles).to be_empty
    post program_coordinators_path(other_program), params: { email: assignee.email }
    expect(response).to have_http_status(:forbidden)
  end

  it 'limits session coordinators to their own session and prevents parent or peer delegation' do
    grant_coordinator_access(program, coordinator)
    sibling = create_program(venue: venue)
    sign_in(coordinator)
    get edit_program_path(program)
    expect(response).to have_http_status(:ok)
    get edit_program_path(sibling)
    expect(response).to have_http_status(:not_found)
    get edit_venue_path(venue)
    expect(response).to have_http_status(:not_found)
    post program_coordinators_path(program), params: { email: coordinator.email }
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
    expect(response.body).to include(venue.name, venue.address, program_path(program))
    expect(response.body).not_to include('Pay', 'Booking History', 'Create Session', 'Session Coordinators')
    expect(response.parsed_body.css('[data-calendar], form')).to be_empty
  end
end
