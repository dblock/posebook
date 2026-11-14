# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Model invitations', :aggregate_failures, :database, type: :request do
  def invitation_token
    URI.decode_www_form(URI(response.parsed_body.at_css('#invitation_link')['value']).query).to_h.fetch('token')
  end

  it 'allows a scoped organizer to create a private link without an email address' do
    venue = create_venue
    organizer = create_user
    grant_schedule_access(venue, organizer)
    sign_in(organizer)
    post venue_model_invitations_path(venue), params: { model_invitation: { name: 'Demo Model' } }
    invitation = track_record(venue.model_invitations.first)
    follow_redirect!
    token = invitation_token
    expect(ModelInvitation.available(token)).to eq(invitation)
    expect(invitation.attributes.values).not_to include(token)
    expect(ActionMailer::Base.deliveries).to be_empty
    get venue_model_invitation_path(venue, invitation)
    expect(response.parsed_body.at_css('#invitation_link')).to be_nil
  end

  it 'sends optional invitation email using the configured mail host' do
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    venue = create_venue
    post venue_model_invitations_path(venue),
         params: { model_invitation: { email: 'model@example.test' }, send_email: '1' }
    track_record(venue.model_invitations.first)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(['model@example.test'])
    expect(mail.body.decoded).to include('http://example.com/invitation?token=')
  end

  it 'keeps a private link when email delivery fails' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    allow(ModelInvitationMailer).to receive(:invite).and_raise(IOError)
    post venue_model_invitations_path(venue),
         params: { model_invitation: { email: 'model@example.test' }, send_email: '1' }
    track_record(venue.model_invitations.first)
    follow_redirect!
    expect(response.body).to include('Email delivery failed.')
    expect(response.parsed_body.at_css('#invitation_link')).to be_present
  end

  it 'rejects invalid addresses and unavailable delivery without persisting an invitation' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    post venue_model_invitations_path(venue), params: { model_invitation: { email: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post venue_model_invitations_path(venue), params: { model_invitation: { email: 'a@example.test' }, send_email: '1' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(venue.model_invitations).to be_empty
  end

  it 'does not let unassigned users or other venues expose or revoke invitations' do
    admin = create_user(roles: ['system_admin'])
    venue = create_venue
    invitation = create_model_invitation(venue, admin)
    sign_in(create_user)
    get new_venue_model_invitation_path(venue)
    expect(response).to have_http_status(:not_found)
    post venue_model_invitations_path(venue), params: { model_invitation: { name: 'Forbidden' } }
    expect(response).to have_http_status(:not_found)
    sign_in(admin)
    delete venue_model_invitation_path(create_venue, invitation)
    expect(response).to have_http_status(:not_found)
    expect(invitation.reload.revoked_at).to be_nil
  end

  it 'does not consume links on GET and blocks revoked, expired, used, and malformed links' do
    admin = create_user(roles: ['system_admin'])
    invitation = create_model_invitation(create_venue, admin)
    get invitation_path(token: invitation.token)
    expect(response).to have_http_status(:ok)
    expect(invitation.reload.used_at).to be_nil
    [{ revoked_at: Time.current }, { expires_at: 1.minute.ago }, { used_at: Time.current }].each do |attributes|
      invalid = create_model_invitation(invitation.venue, admin, **attributes)
      get invitation_path(token: invalid.token)
      expect(response).to have_http_status(:gone)
    end
    get invitation_path(token: 'invalid')
    expect(response).to have_http_status(:gone)
  end

  it 'registers an invited user with model access only at the inviting venue' do
    invitation = create_model_invitation(create_venue, create_user(roles: ['system_admin']))
    attributes = user_attributes(roles: ['system_admin'], display_name: 'Artist Model', instagram_url: '@Artist.Model',
                                 instagram_tagging_allowed: '1')
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    user = track_record(User.find_by(email: attributes[:email]))
    membership = track_model_membership(invitation.venue, user)
    expect(response).to redirect_to(venue_path(invitation.venue))
    expect(user).to have_attributes(roles: [], display_name: 'Artist Model', instagram_tagging_allowed: true,
                                    instagram_url: 'https://www.instagram.com/artist.model/')
    expect(membership.roles).to eq(['model'])
    expect(invitation.reload.used_by_id).to eq(user.id)
    get venue_path(invitation.venue)
    expect(response.body).not_to include('Invite a Model', 'Existing user', 'Edit Venue')
    get venue_path(create_venue)
    expect(response).to have_http_status(:not_found)
  end

  it 'returns an existing account to its invitation after login' do
    user = create_user
    invitation = create_model_invitation(create_venue, create_user(roles: ['system_admin']))
    get invitation_path(token: invitation.token)
    sign_in(user)
    expect(response).to redirect_to(invitation_path(token: invitation.token))
    post invitation_path, params: { token: invitation.token }
    membership = track_model_membership(invitation.venue, user)
    expect(response).to redirect_to(venue_path(invitation.venue))
    expect(membership.roles).to eq(['model'])
    post invitation_path, params: { token: invitation.token }
    expect(response).to have_http_status(:gone)
  end

  it 'preserves existing organizer roles when the same user joins as a model' do
    user = create_user
    venue = create_venue
    membership = grant_schedule_access(venue, user)
    invitation = create_model_invitation(venue, create_user(roles: ['system_admin']))
    sign_in(user)
    post invitation_path, params: { token: invitation.token }
    expect(membership.reload.roles).to contain_exactly('manage_schedule', 'model')
    expect(VenueMembership.where(venue_id: venue.id, user_id: user.id).count).to eq(1)
  end

  it 'does not consume an invitation or create an account when registration is invalid' do
    invitation = create_model_invitation(create_venue, create_user(roles: ['system_admin']))
    attributes = user_attributes(password: 'short', password_confirmation: 'short')
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Password is too short')
    expect(User.where(email: attributes[:email])).to be_empty
    expect(ModelInvitation.available(invitation.token)).to be_present
    expect(invitation.venue.memberships).to be_empty
  end

  it 'revokes pending invitations without deleting their history' do
    admin = create_user(roles: ['system_admin'])
    invitation = create_model_invitation(create_venue, admin)
    sign_in(admin)
    delete venue_model_invitation_path(invitation.venue, invitation)
    expect(response).to redirect_to(venue_path(invitation.venue))
    expect(invitation.reload.status).to eq('Revoked')
    expect(ModelInvitation.available(invitation.token)).to be_nil
  end
end
