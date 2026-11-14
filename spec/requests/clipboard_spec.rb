# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Copy controls', :aggregate_failures, :database, type: :request do
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:program) { create_program }

  it 'copies exact profile values while safely escaping names and preserving contact links' do
    user = create_user(name: 'Avery <Artist> "Studio"', phone: '+12125551234', instagram_handle: '@alex.artist')
    sign_in(user)
    get profile_path
    buttons = response.parsed_body.css('.copy-button')
    expect(buttons.pluck('data-copy-value'))
      .to include(user.name, user.email, user.phone, '@alex.artist')
    expect(buttons.all? { |button| button['type'] == 'button' && button.key?('hidden') }).to be(true)
    expect(response.parsed_body.css('dd artist')).to be_empty
    expect(response.parsed_body.at_css('a[href="https://www.instagram.com/alex.artist/"]')).to be_present
  end

  it 'does not offer copy controls for missing contact fields' do
    sign_in(create_user)
    get profile_path
    expect(response.parsed_body.at_css('[aria-label="Copy phone number"]')).to be_nil
    expect(response.parsed_body.at_css('[aria-label="Copy Instagram handle"]')).to be_nil
    expect(response.parsed_body.css('.copy-button').pluck('data-copy-value'))
      .not_to include('Not provided')
  end

  it 'copies the participant invitation field only while its single-use link is displayed' do
    sign_in(admin)
    post program_participant_invitations_path(program),
         params: { participant_invitation: { name: 'Avery Artist', email: 'artist@example.test' } }
    invitation = track_record(program.participant_invitations.first)
    follow_redirect!
    button = response.parsed_body.at_css('[data-copy-target="invitation_link"]')
    expect(button['aria-label']).to eq('Copy private invitation link')
    expect(button['data-copy-value']).to eq('')
    field = response.parsed_body.at_css('.copy-field')
    expect(field.at_css('[data-copy-target="invitation_link"]')).to eq(button)
    expect(field.at_css('#invitation_link')['value']).to include('/invitation?token=')
    expect(response.body).to include('Only artist@example.test can accept it.')
    get program_participant_invitation_path(program, invitation)
    expect(response.parsed_body.at_css('[data-copy-target]')).to be_nil
  end

  it 'retains coordinator history links and email copy controls for optional recipient addresses' do
    named = create_coordinator_invitation(program.venue, admin, email: nil, name: 'Invited Manager')
    unnamed = create_coordinator_invitation(program.venue, admin, email: nil, name: nil)
    restricted = create_coordinator_invitation(program.venue, admin, email: 'manager@example.test')
    sign_in(admin)
    get venue_coordinators_path(program.venue)
    expect(response.parsed_body.at_css("a[href='#{venue_coordinator_invitation_path(program.venue, named)}']").text)
      .to eq('Invited Manager')
    expect(response.parsed_body.at_css("a[href='#{venue_coordinator_invitation_path(program.venue, unnamed)}']").text)
      .to eq('Personal invitation')
    expect(response.parsed_body.at_css('[data-copy-value="manager@example.test"]')).to be_present
    get venue_coordinator_invitation_path(program.venue, restricted)
    expect(response.parsed_body.at_css('[data-copy-value="manager@example.test"]')).to be_present
    expect(response.body).to include('using the invited email address')
    get venue_coordinator_invitation_path(program.venue, named)
    expect(response.body).to include('No email restriction.')
    expect(response.parsed_body.at_css('[aria-label="Copy invited email"]')).to be_nil
  end

  it 'copies coordinator invitation fields without recovering tokens on later visits' do
    sign_in(admin)
    post venue_coordinators_path(program.venue), params: { email: 'manager@example.test' }
    invitation = track_record(CoordinatorInvitation.find_by(venue_id: program.venue.id))
    follow_redirect!
    field = response.parsed_body.at_css('.copy-field')
    expect(field.at_css('[data-copy-target]')['data-copy-target']).to eq('invitation_link')
    expect(field.at_css('#invitation_link')['value']).to include('/coordinator_invitation?token=')
    get venue_coordinator_invitation_path(program.venue, invitation)
    expect(response.parsed_body.at_css('[data-copy-target]')).to be_nil
    expect(response.parsed_body.at_css('[data-copy-value="manager@example.test"]')).to be_present
  end

  it 'offers public address and canonical sharing links without leaking account contacts or access tokens' do
    user = create_user(phone: '+12125551234', instagram_handle: '@private.artist')
    grant_participant_access(program, user)
    get program_path(program, token: 'private-token')
    values = response.parsed_body.css('.copy-button').pluck('data-copy-value')
    expect(values).to include(program.address, program_url(program))
    expect(values).not_to include(user.name, user.email, user.phone, '@private.artist')
    expect(values.join).not_to include('private-token')
    get venue_path(program.venue)
    expect(response.parsed_body.at_css('[aria-label="Copy venue link"]')['data-copy-value'])
      .to eq(venue_url(program.venue))
  end

  it 'offers contact copying to authorized admins but not unauthorized account-list visitors' do
    user = create_user(phone: '+12125551234')
    sign_in(admin)
    get admin_users_path
    values = response.parsed_body.css('.copy-button').pluck('data-copy-value')
    expect(values).to include(user.name, user.email, user.phone)
    sign_in(user)
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.at_css('.copy-button')).to be_nil
  end
end
