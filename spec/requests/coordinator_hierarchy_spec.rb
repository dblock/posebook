# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinator hierarchy', :aggregate_failures, :database, type: :request do
  let(:venue) { create_venue }
  let(:program) { create_program(venue: venue) }
  let(:other_program) { create_program }
  let(:coordinator) { create_user }

  it 'shows coordinator portraits and keeps the invitation action below the list without access guidance' do
    grant_venue_access(venue, coordinator)
    assignee = create_user
    grant_coordinator_access(program, assignee)
    photo = assignee.profile_photos.create!(public: true)
    sign_in(coordinator)
    get program_coordinators_path(program)
    expect(response.parsed_body.at_css('.participant-portrait img')['src'])
      .to eq(participant_photo_path(assignee, photo.id, thumbnail: 1))
    expect(response.parsed_body.at_css('main > p:last-child a')['href']).to eq(new_program_coordinator_path(program))
    expect(response.body).not_to include('inherit access to every', 'coordinators cannot grant coordinator access.')
    expect(response.parsed_body.at_css('.coordinator-list td a:not(.participant-portrait)')['href'])
      .to eq(participant_path(assignee))
    expect(response.parsed_body.at_css("a[href='mailto:#{assignee.email}']")).to be_nil
  end

  it 'keeps invalid venue creation and editing on their forms without changing stored locations' do
    sign_in(create_user(roles: ['system_admin']))
    get new_venue_path
    expect(response).to have_http_status(:ok)
    expect { post venues_path, params: { venue: { name: '', address: '' } } }.not_to change(Venue, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.text).to include("Name can't be blank", "Address can't be blank")
    name = venue.name
    patch venue_path(venue), params: { venue: { name: '' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(venue.reload.name).to eq(name)
  end

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

  it 'lets admins create venues with public descriptions' do
    sign_in(create_user(roles: ['system_admin']))
    post venues_path, params: { venue: { name: "Studio #{SecureRandom.hex(4)}", address: 'Test address',
                                         description: '**Public studio description**' } }
    created = track_record(Venue.find(response.location.split('/').last))
    expect(response).to redirect_to(venue_path(created))
    expect(created.description).to eq('**Public studio description**')
  end

  it 'allows venue coordinators to create sessions only at their own venue' do
    grant_venue_access(venue, coordinator)
    sign_in(coordinator)
    post venue_programs_path(venue),
         params: { program: { name: 'Tuesday Booking', available_weekdays: ['2'],
                              description: '**Public program description**' } }
    created = track_record(venue.programs.find_by(name: 'Tuesday Booking'))
    expect(response).to redirect_to(program_path(created))
    expect(created.description).to eq('**Public program description**')
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
    expect(response.body).to include('This Email Is Already Registered', 'Grant Program Coordinator Access')
    expect(program.memberships.where(user_id: assignee.id)).to be_empty
    post program_coordinators_path(program), params: { email: assignee.email, grant_access: '1',
                                                       roles: ['system_admin'] }
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
    expect(response.parsed_body.css('.program-secondary-tabs a').map(&:text)).to eq(['Details', 'Google Calendar'])
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
    post venue_coordinators_path(venue), params: { email: coordinator.email, grant_access: '1' }
    membership = track_record(VenueMembership.find_by(venue_id: venue.id, user_id: coordinator.id))
    expect(program.managed_by?(coordinator)).to be(true)
    delete venue_coordinator_path(venue, membership)
    expect(program.managed_by?(coordinator)).to be(false)
    expect(coordinator.reload.roles).to be_empty
  end

  it 'publishes location details and a separate program tab without private session information' do
    program
    get venue_path(venue)
    expect(response.body).to include(venue.name, venue.address, program_path(program))
    expect(response.body).not_to include('Pay', 'Booking History', 'New Program', 'Program Coordinators')
    expect(response.parsed_body.css('[data-calendar], form')).to be_empty
    expect(response.parsed_body.at_css('.venue-tabs')).to be_nil
    get programs_venue_path(venue)
    expect(response.body).to include(program_path(program))
    expect(response.body).not_to include('Pay', 'Booking History', 'New Program')
  end
end
