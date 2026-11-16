# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Copy controls', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:admin) { create_user(roles: ['system_admin']) }
  let(:program) { create_program }

  it 'displays profile values without copy buttons while safely escaping names and preserving links' do
    user = create_user(name: 'Avery <Artist> "Studio"', phone: '+12125551234', instagram_handle: '@alex.artist')
    user.set(pending_email: 'pending@example.test')
    sign_in(user)
    get profile_path
    expect(response.parsed_body.css('.copy-button')).to be_empty
    expect(response.parsed_body.css('dd').text).to include(user.name, user.email, user.display_phone, '@alex.artist')
    expect(response.body).to include('pending@example.test')
    expect(response.parsed_body.css('dd artist')).to be_empty
    expect(response.parsed_body.at_css('a[href="https://www.instagram.com/alex.artist/"]')).to be_present
  end

  it 'copies the participant invitation field only while its single-use link is displayed' do
    sign_in(admin)
    post program_participant_invitations_path(program),
         params: { participant_invitation: { name: 'Avery Artist', email: 'artist@example.test' } }
    invitation = track_record(program.participant_invitations.first)
    follow_redirect!
    button = response.parsed_body.at_css('[data-copy-target="invitation_link"]')
    expect(button['aria-label']).to eq('Copy private invitation link')
    expect(button['type']).to eq('button')
    expect(button.key?('hidden')).to be(true)
    expect(response.parsed_body.css('.copy-button').length).to eq(1)
    field = response.parsed_body.at_css('.copy-field')
    expect(field.at_css('[data-copy-target="invitation_link"]')).to eq(button)
    expect(field.at_css('#invitation_link')['value']).to include('/invitation?token=')
    expect(response.body).to include('Only artist@example.test can accept it.')
    get program_participant_invitation_path(program, invitation)
    expect(response.parsed_body.at_css('[data-copy-target]')).to be_nil
  end

  it 'retains coordinator history links and optional recipient addresses without email copy buttons' do
    named = create_coordinator_invitation(program.venue, admin, email: nil, name: 'Invited Manager')
    unnamed = create_coordinator_invitation(program.venue, admin, email: nil, name: nil)
    restricted = create_coordinator_invitation(program.venue, admin, email: 'manager@example.test')
    sign_in(admin)
    get new_venue_coordinator_path(program.venue)
    expect(response.parsed_body.at_css("a[href='#{venue_coordinator_invitation_path(program.venue, named)}']").text)
      .to eq('Invited Manager')
    expect(response.parsed_body.at_css("a[href='#{venue_coordinator_invitation_path(program.venue, unnamed)}']").text)
      .to eq('Personal invitation')
    expect(response.parsed_body.at_css("a[href='#{polymorphic_path([program.venue, restricted])}']").text)
      .to eq('manager@example.test')
    expect(response.parsed_body.css('.copy-button')).to be_empty
    get venue_coordinator_invitation_path(program.venue, restricted)
    expect(response.parsed_body.css('.copy-button')).to be_empty
    expect(response.body).to include('Invited email: manager@example.test')
    get venue_coordinator_invitation_path(program.venue, named)
    expect(response.body).to include('No email restriction.')
  end

  %i[venue program].each do |scope|
    it "copies only the #{scope} coordinator invitation link without recovering tokens on later visits" do
      target = scope == :venue ? program.venue : program
      sign_in(admin)
      post polymorphic_path([target, :coordinators]), params: { email: 'manager@example.test' }
      follow_redirect!
      invitation = track_record(CoordinatorInvitation.find(response.request.path.split('/').last))
      field = response.parsed_body.at_css('.copy-field')
      expect(field.at_css('[data-copy-target]')['data-copy-target']).to eq('invitation_link')
      expect(field.at_css('#invitation_link')['value']).to include('/coordinator_invitation?token=')
      expect(response.parsed_body.css('.copy-button').length).to eq(1)
      get polymorphic_path([target, invitation])
      expect(response.parsed_body.css('.copy-button')).to be_empty
      expect(response.body).to include('Invited email: manager@example.test')
    end

    it "copies the canonical #{scope} URL without query strings while retaining authorized information" do
      program = create_program(program_label: 'Figure Drawing Session', instagram_handle: '@preview.studio')
      resource = scope == :venue ? program.venue : program
      sign_in(admin)
      get polymorphic_path(resource), params: { token: 'private-token' }
      button = response.parsed_body.at_css('.copy-button')
      url = "#{request.base_url}#{polymorphic_path(resource)}"
      expect(button.text).to eq('Copy Link')
      expect(button['data-copy-link']).to eq(url)
      expect(button.key?('hidden')).to be(true)
      expect(response.parsed_body.css('.title-row .copy-button').length).to eq(1)
      fallback = response.parsed_body.at_css('.copy-fallback')
      expect([fallback['href'], fallback.text]).to eq([url, url])
      expect(response.body).to include(resource.address)
      expect(response.body).not_to include('Figure Drawing Session Link', 'Venue Link')
      expect(response.parsed_body.at_css('a[href="https://www.instagram.com/preview.studio/"]')).to be_present
    end
  end

  it 'retains authorized account details without copy buttons' do
    user = create_user(phone: '+12125551234')
    sign_in(admin)
    get admin_users_path
    expect(response.parsed_body.css('.copy-button')).to be_empty
    expect(response.body).to include(user.name, user.email, user.display_phone)
    sign_in(user)
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.at_css('.copy-button')).to be_nil
  end

  [[true, true, 'Open'], [false, true, 'Closed'], [true, false, 'Closed']].each do |enabled, active, status|
    it "shows managers a visible application URL and copy control when intake is #{enabled} and active is #{active}" do
      program.update!(applications_enabled: enabled, active: active)
      coordinator = create_user
      grant_coordinator_access(program, coordinator)
      sign_in(coordinator)
      get program_path(program), params: { token: 'private-token' }
      sharing = response.parsed_body.at_css('#application-sharing')
      link = sharing.at_css('.copy-visible-link')
      button = sharing.at_css('.copy-button')
      expect([link['href'], link.text, button['data-copy-link']]).to eq([program_apply_url(program)] * 3)
      expect(sharing.text).to include(status)
      expect(sharing.css('a').length).to eq(1)
      expect(button.text).to eq('Copy Link')
      expect(button['aria-label']).to eq('Copy application link')
      expect(button.key?('hidden')).to be(true)
    end
  end

  it 'keeps application sharing tools off public and ordinary participant views' do
    program.update!(applications_enabled: true)
    get program_path(program)
    expect(response.parsed_body.at_css('#application-sharing')).to be_nil
    participant = create_user
    grant_participant_access(program, participant)
    sign_in(participant)
    get program_path(program)
    expect(response.parsed_body.at_css('#application-sharing')).to be_nil
    expect(response.parsed_body.css('.copy-button').length).to eq(1)
  end

  it 'retains roster, invitation and coordinator information without copy buttons' do
    user = create_user
    grant_participant_access(program, user)
    organizer = create_user
    grant_coordinator_access(program, organizer)
    grant_venue_access(program.venue, organizer)
    invitation = create_participant_invitation(program, admin, email: 'invited@example.test')
    sign_in(admin)
    [program_participants_path(program), program_participant_invitations_path(program),
     program_coordinators_path(program), venue_coordinators_path(program.venue)].each do |path|
      get path
      expect(response.parsed_body.css('.copy-button')).to be_empty
    end
    get program_participants_path(program)
    expect(response.body).to include(user.name, user.email)
    expect(response.body).not_to include(invitation.email)
    get program_participant_invitations_path(program)
    expect(response.body).to include(invitation.email)
  end

  it 'retains calendar Instagram and organizer contact links without copy buttons' do
    user = create_user(instagram_handle: '@preview.artist', instagram_tagging_allowed: true)
    grant_participant_access(program, user)
    track_booking(BookingMutation.new(program: program, user: user).book(date: '2026-11-16'))
    organizer = create_user(phone: '+12125551234')
    grant_coordinator_access(program, organizer)
    sign_in(user)
    get program_path(program, section: 'calendar')
    expect(response.parsed_body.css('.copy-button')).to be_empty
    expect(response.parsed_body.at_css('a[href="https://www.instagram.com/preview.artist/"]')).to be_present
    expect(response.parsed_body.at_css("a[href='mailto:#{organizer.email}']")).to be_present
    expect(response.parsed_body.at_css("a[href='tel:#{organizer.phone}']")).to be_present
  end
end
