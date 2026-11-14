# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Venue management', :aggregate_failures, :database, type: :request do
  it 'requires authentication' do
    create_user
    get venues_path
    expect(response).to redirect_to(new_session_path)
    get venue_organizers_path(create_venue)
    expect(response).to redirect_to(new_session_path)
  end

  it 'lets a system admin create and update venue settings' do
    sign_in(create_user(roles: ['system_admin']))
    get new_venue_path
    expect(response).to have_http_status(:ok)
    post venues_path, params: { venue: { name: "Enoch's", address: '480 10th Avenue, New York',
                                         time_zone: 'America/New_York', model_pay: '140.00' } }
    venue = track_record(Venue.find_by(name: "Enoch's"))
    expect(response).to redirect_to(venue_path(venue))
    get edit_venue_path(venue)
    expect(response).to have_http_status(:ok)
    patch venue_path(venue), params: { venue: { instructions: 'Please arrive at 6:15 PM.', booking_horizon_months: 9,
                                                available_weekdays: ['', '1', '3'] } }
    expect(venue.reload.booking_horizon_months).to eq(9)
    expect(venue.instructions).to eq('Please arrive at 6:15 PM.')
    expect(venue.available_weekdays).to eq(%w[1 3])
  end

  it 'renders validation errors when creating or editing a venue' do
    sign_in(create_user(roles: ['system_admin']))
    post venues_path, params: { venue: { name: '', address: '', time_zone: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    venue = create_venue
    patch venue_path(venue), params: { venue: { name: '' } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'limits organizers to their assigned venues and hides other users' do
    venue = create_venue
    other = create_venue
    user = create_user
    grant_schedule_access(venue, user)
    sign_in(user)
    get venues_path
    expect(response.body).to include(venue.name)
    expect(response.body).not_to include(other.name)
    get venue_path(venue)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Existing user', 'Edit Venue', 'Organizers')
    get venue_organizers_path(venue)
    expect(response).to have_http_status(:forbidden)
    get venue_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it 'does not allow schedule access to grant venue or user administration' do
    venue = create_venue
    user = create_user
    grant_schedule_access(venue, user)
    sign_in(user)
    get new_venue_path
    expect(response).to have_http_status(:forbidden)
    post venues_path, params: { venue: { name: 'Forbidden' } }
    expect(response).to have_http_status(:forbidden)
    patch venue_path(venue), params: { venue: { name: 'Forbidden' } }
    expect(response).to have_http_status(:forbidden)
    post venue_organizers_path(venue), params: { user_id: user.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'shows an empty venue list to users without assignments' do
    sign_in(create_user)
    get venues_path
    expect(response.body).to include('No venues assigned')
  end

  it 'lets a system admin grant and revoke schedule access without deleting membership history' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    user = create_user
    post venue_organizers_path(venue), params: { user_id: user.id, roles: ['system_admin'] }
    membership = track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
    expect(response).to redirect_to(venue_organizers_path(venue))
    expect(membership.roles).to eq(['manage_schedule'])
    expect(user.reload.roles).to be_empty
    delete venue_organizer_path(venue, membership)
    expect(response).to redirect_to(venue_organizers_path(venue))
    expect(membership.reload.roles).to be_empty
    expect(Venue.visible_to(user)).to be_empty
  end

  it 'does not let organizer removal target a membership at another venue' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    membership = grant_schedule_access(create_venue, create_user)
    delete venue_organizer_path(venue, membership)
    expect(response).to have_http_status(:not_found)
    expect(membership.reload.roles).to eq(['manage_schedule'])
  end

  it 'does not assign inactive users' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    user = create_user(active: false)
    post venue_organizers_path(venue), params: { user_id: user.id }
    expect(response).to have_http_status(:not_found)
    expect(VenueMembership.where(venue_id: venue.id)).to be_empty
  end

  it 'shows assignment controls only to admins and labels inactive organizers' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    user = create_user
    grant_schedule_access(venue, user)
    user.set(active: false)
    get venue_organizers_path(venue)
    expect(response.body).to include('inactive account', 'Remove Schedule Access', 'Existing user')
    options = response.parsed_body.css('select[name="user_id"]').text
    expect(options).not_to include(user.email)
  end

  it 'links to a separate organizer page beside venue editing without exposing controls on the venue' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    user = create_user
    get venue_path(venue)
    links = response.parsed_body.css('main > p').find { |paragraph| paragraph.text.include?('Edit Venue') }
    expect(links.css('a').pluck('href')).to eq([edit_venue_path(venue), venue_organizers_path(venue)])
    expect(response.body).not_to include('Grant Schedule Access', 'Remove Schedule Access', user.email)
    get venue_organizers_path(venue)
    expect(response.body).to include('No organizers assigned.', 'Grant Schedule Access', user.email)
    expect(response.parsed_body.at_css('main a')['href']).to eq(venue_path(venue))
    sign_in(user)
    get venue_organizers_path(venue)
    expect(response).to have_http_status(:forbidden)
  end
end
