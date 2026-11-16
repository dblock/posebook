# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Invitation recipient restrictions', :aggregate_failures, :database, type: :request do
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:venue) { create_venue }
  let(:program) { create_program(venue: venue) }
  let(:recipient) { create_user }

  def accept_path
    scope == :participant ? invitation_path : coordinator_invitation_path
  end

  def register_path
    scope == :participant ? invited_registration_path : coordinator_invited_registration_path
  end

  def session_key
    scope == :participant ? :invitation_token : :coordinator_invitation_token
  end

  def destination
    return venue_path(venue) if scope == :venue

    program_path(program, section: ('calendar' if scope == :participant))
  end

  def recipient_invitation(email)
    if scope == :participant
      create_participant_invitation(program, admin, email: email, name: 'Invited Artist')
    else
      create_coordinator_invitation(scope == :venue ? venue : program, admin, email: email, name: 'Invited Artist')
    end
  end

  def track_granted_membership(user)
    if scope == :venue
      track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
    else
      track_participant_membership(program, user)
    end
  end

  shared_examples 'optional recipient email' do
    it 'defaults tagging on and requires a valid handle before accepting an invitation' do
      invitation = recipient_invitation(nil)
      get accept_path, params: { token: invitation.token }
      expect(response.parsed_body.at_css('input[type="checkbox"][name="user[instagram_tagging_allowed]"]')['checked'])
        .to be_present
      attributes = user_attributes(instagram_tagging_allowed: '1')
      post register_path, params: { token: invitation.token, user: attributes }
      expect(response).to have_http_status(:unprocessable_content)
      expect(invitation.reload.used_at).to be_nil
      post register_path,
           params: { token: invitation.token, user: attributes.merge(instagram_handle: '@Preview.Artist') }
      registered = track_record(User.find_by(email: attributes[:email]))
      track_granted_membership(registered)
      expect(response).to redirect_to(destination)
      expect(registered).to have_attributes(instagram_handle: 'preview.artist', instagram_tagging_allowed: true)
    end

    it 'requires phone and gender without consuming the invitation' do
      invitation = recipient_invitation(nil)
      get accept_path, params: { token: invitation.token }
      expect(response.parsed_body.at_css('input[name="user[phone]"][required]')).to be_present
      expect(response.parsed_body.at_css('select[name="user[gender]"][required]')).to be_present
      attributes = user_attributes(phone: '', gender: '')
      post register_path, params: { token: invitation.token, user: attributes }
      expect(response).to have_http_status(:unprocessable_content)
      expect(invitation.reload.used_at).to be_nil
      expect(User.where(email: attributes[:email])).to be_empty
      post register_path, params: { token: invitation.token, user: user_attributes(email: attributes[:email]) }
      registered = track_record(User.find_by(email: attributes[:email]))
      track_granted_membership(registered)
      expect(response).to redirect_to(destination)
      expect(invitation.reload.used_by_id).to eq(registered.id)
    end

    it 'allows an existing account to accept a blank-email link' do
      invitation = recipient_invitation(' ')
      sign_in(recipient)
      post register_path, params: { token: invitation.token }
      expect(response).to redirect_to("#{accept_path}?token=#{invitation.token}")
      expect(invitation.reload.used_at).to be_nil
      post accept_path, params: { token: invitation.token }
      track_granted_membership(recipient)
      expect(response).to redirect_to(destination)
      expect(invitation.reload).to have_attributes(email: nil, used_by_id: recipient.id)
    end

    it 'allows a chosen registration email for a link without a recipient address' do
      invitation = recipient_invitation(nil)
      get accept_path, params: { token: invitation.token }
      expect(response.parsed_body.at_css('#user_email')['readonly']).to be_nil
      expect(response.parsed_body.at_css('#user_name')['value']).to eq(invitation.name)
      attributes = user_attributes(phone: '1 (212) 555-1234')
      post register_path, params: { token: invitation.token, user: attributes }
      user = track_record(User.find_by(email: attributes[:email]))
      track_granted_membership(user)
      expect(response).to redirect_to(destination)
      expect(invitation.reload.used_by_id).to eq(user.id)
      expect(user.phone).to eq('+12125551234')
    end

    it 'shows logout guidance and rejects acceptance by a different signed-in account' do
      invitation = recipient_invitation(recipient.email)
      wrong = create_user
      sign_in(wrong)
      get accept_path, params: { token: invitation.token }
      expect(response.body).to include('Sign Out and Use the Invited Account', recipient.email)
      expect(response.parsed_body.css('form input[name=token]')).to be_empty
      post accept_path, params: { token: invitation.token }
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('Sign Out and Use the Invited Account')
      expect(invitation.reload.used_at).to be_nil
      expect(User.find(wrong.id).email).to eq(wrong.email)
    end

    it 'keeps the invitation across logout and returns the correct account to acceptance' do
      invitation = recipient_invitation(recipient.email)
      sign_in(create_user)
      get accept_path, params: { token: invitation.token }
      delete session_path, params: { session_key => invitation.token }
      expect(response).to redirect_to("#{accept_path}?token=#{invitation.token}")
      follow_redirect!
      expect(response.parsed_body.at_css('#user_email')['value']).to eq(recipient.email)
      expect(response.parsed_body.at_css('#user_email')['readonly']).to be_present
      sign_in(recipient)
      expect(response).to redirect_to("#{accept_path}?token=#{invitation.token}")
      post accept_path, params: { token: invitation.token }
      track_granted_membership(recipient)
      expect(response).to redirect_to(destination)
      expect(invitation.reload.used_by_id).to eq(recipient.id)
    end

    it 'rejects a forged registration email without consuming the link and accepts the normalized address' do
      invitation = recipient_invitation('invited@example.test')
      attributes = user_attributes
      post register_path, params: { token: invitation.token, user: attributes }
      expect(response).to have_http_status(:unprocessable_content)
      expect(User.where(email: attributes[:email])).to be_empty
      expect(invitation.reload.used_at).to be_nil
      expect(response.parsed_body.at_css('#user_email')['value']).to eq(invitation.email)
      expect(response.parsed_body.at_css('#user_email')['readonly']).to be_present
      post register_path, params: { token: invitation.token, user: attributes.merge(email: ' INVITED@EXAMPLE.TEST ') }
      user = track_record(User.find_by(email: invitation.email))
      track_granted_membership(user)
      expect(response).to redirect_to(destination)
      expect(invitation.reload.used_by_id).to eq(user.id)
    end
  end

  context 'with a participant invitation' do
    let(:scope) { :participant }

    it_behaves_like 'optional recipient email'
  end

  context 'with a venue coordinator invitation' do
    let(:scope) { :venue }

    it_behaves_like 'optional recipient email'
  end

  context 'with a session coordinator invitation' do
    let(:scope) { :program }

    it_behaves_like 'optional recipient email'
  end
end
