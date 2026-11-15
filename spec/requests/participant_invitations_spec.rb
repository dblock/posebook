# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Participant invitations', :aggregate_failures, :database, type: :request do
  def invitation_token
    URI.decode_www_form(URI(response.parsed_body.at_css('#invitation_link')['value']).query).to_h.fetch('token')
  end

  it 'formats invitation recipients from their available details without exposing matching accounts' do
    admin = create_user(roles: ['system_admin'])
    program = create_program
    unknown = create_user(name: 'Private account name', gender: 'female', public_profile_private: true)
    recipients = [{ name: 'Drawing <Model> & Artist', email: 'artist@example.test' },
                  { email: unknown.email }, { name: 'Named guest' }, {}]
    recipients.each { |attributes| create_participant_invitation(program, admin, **attributes) }
    sign_in(admin)
    get program_participants_path(program)
    expect(response.parsed_body.css('.invitation-recipient').map(&:text))
      .to contain_exactly('Drawing <Model> & Artist <artist@example.test>', unknown.email, 'Named guest',
                          'Personal invitation')
    expect(response.body).not_to include(unknown.name, '(Female)')
  end

  it 'allows a scoped organizer to create a private link without an email address' do
    program = create_program
    organizer = create_user
    grant_coordinator_access(program, organizer)
    sign_in(organizer)
    post program_participant_invitations_path(program), params: { participant_invitation: { name: 'Demo Participant' } }
    invitation = track_record(program.participant_invitations.first)
    follow_redirect!
    expect(response.parsed_body.at_css('.status-label-warning').text).to eq('Pending')
    token = invitation_token
    expect(ParticipantInvitation.available(token)).to eq(invitation)
    expect(invitation.attributes.values).not_to include(token)
    expect(ActionMailer::Base.deliveries).to be_empty
    get program_participant_invitation_path(program, invitation)
    expect(response.parsed_body.at_css('#invitation_link')).to be_nil
  end

  it 'sends optional invitation email using the configured mail host' do
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    program = create_program(start_time: '19:15', available_weekdays: ['2'],
                             time_zone: 'America/Los_Angeles')
    post program_participant_invitations_path(program),
         params: { participant_invitation: { email: 'participant@example.test' }, send_email: '1' }
    track_record(program.participant_invitations.first)
    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_nil
    deliver_emails
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(['participant@example.test'])
    expect(mail.body.decoded).to include('http://example.com/invitation?token=',
                                         'Tuesday at 7:15 PM (America/Los_Angeles)', 'using participant@example.test')
  end

  it 'creates a link without email or SMTP even when email delivery is checked' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post program_participant_invitations_path(program),
         params: { participant_invitation: { name: 'Invited Artist' }, send_email: '1' }
    invitation = track_record(program.participant_invitations.first)
    follow_redirect!
    expect(response.parsed_body.at_css('#invitation_link')['value']).to include('/invitation?token=')
    expect(invitation.email).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'keeps a private link when email cannot be queued' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    error = ActiveJob::EnqueueError.new('Unavailable')
    allow(EmailDeliveryJob).to receive(:perform_later).and_raise(error)
    allow(NewRelic::Agent).to receive(:notice_error)
    post program_participant_invitations_path(program),
         params: { participant_invitation: { email: 'participant@example.test' }, send_email: '1' }
    track_record(program.participant_invitations.first)
    follow_redirect!
    expect(response.body).to include('Email could not be queued.')
    expect(response.parsed_body.at_css('#invitation_link')).to be_present
    expect(NewRelic::Agent).to have_received(:notice_error).with(an_instance_of(EmailDelivery::Unavailable)).once
  end

  it 'rejects invalid addresses and unavailable delivery without persisting an invitation' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    post program_participant_invitations_path(program), params: { participant_invitation: { email: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post program_participant_invitations_path(program),
         params: { participant_invitation: { email: 'a@example.test' }, send_email: '1' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(program.participant_invitations).to be_empty
  end

  it 'does not let unassigned users or other sessions expose or revoke invitations' do
    admin = create_user(roles: ['system_admin'])
    program = create_program
    invitation = create_participant_invitation(program, admin)
    sign_in(create_user)
    get new_program_participant_invitation_path(program)
    expect(response).to have_http_status(:not_found)
    post program_participant_invitations_path(program), params: { participant_invitation: { name: 'Forbidden' } }
    expect(response).to have_http_status(:not_found)
    sign_in(admin)
    delete program_participant_invitation_path(create_program, invitation)
    expect(response).to have_http_status(:not_found)
    expect(invitation.reload.revoked_at).to be_nil
  end

  it 'does not consume links on GET and blocks revoked, expired, used, and malformed links' do
    admin = create_user(roles: ['system_admin'])
    invitation = create_participant_invitation(create_program, admin)
    get invitation_path(token: invitation.token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Monday at 9:00 AM (UTC)')
    expect(invitation.reload.used_at).to be_nil
    [{ revoked_at: Time.current }, { expires_at: 1.minute.ago }, { used_at: Time.current }].each do |attributes|
      invalid = create_participant_invitation(invitation.program, admin, **attributes)
      get invitation_path(token: invalid.token)
      expect(response).to have_http_status(:gone)
    end
    get invitation_path(token: 'invalid')
    expect(response).to have_http_status(:gone)
  end

  it 'registers an invited user with participant access only at the inviting program' do
    invitation = create_participant_invitation(create_program, create_user(roles: ['system_admin']))
    attributes = user_attributes(roles: ['system_admin'], display_name: 'Public Participant',
                                 instagram_handle: '@Public.Participant',
                                 instagram_tagging_allowed: '1')
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    user = track_record(User.find_by(email: attributes[:email]))
    membership = track_participant_membership(invitation.program, user)
    expect(response).to redirect_to(program_path(invitation.program, section: 'calendar'))
    expect(user).to have_attributes(roles: [], display_name: 'Public Participant', instagram_tagging_allowed: true,
                                    instagram_handle: 'public.participant')
    expect(membership.roles).to eq(['participant'])
    expect(invitation.reload.used_by_id).to eq(user.id)
    get program_path(invitation.program)
    expect(response.body).not_to include('Invite a Participant', 'Existing user', 'Edit Program')
    get program_path(create_program)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Instructions', 'Pay', 'Manage Schedule')
  end

  it 'returns an existing account to its invitation after login' do
    user = create_user
    invitation = create_participant_invitation(create_program, create_user(roles: ['system_admin']))
    get invitation_path(token: invitation.token)
    sign_in(user)
    expect(response).to redirect_to(invitation_path(token: invitation.token))
    post invitation_path, params: { token: invitation.token }
    membership = track_participant_membership(invitation.program, user)
    expect(response).to redirect_to(program_path(invitation.program, section: 'calendar'))
    expect(membership.roles).to eq(['participant'])
    post invitation_path, params: { token: invitation.token }
    expect(response).to have_http_status(:gone)
  end

  it 'preserves existing organizer roles when the same user joins as a participant' do
    user = create_user
    program = create_program
    membership = grant_coordinator_access(program, user)
    invitation = create_participant_invitation(program, create_user(roles: ['system_admin']))
    sign_in(user)
    post invitation_path, params: { token: invitation.token }
    expect(membership.reload.roles).to contain_exactly('program_coordinator', 'participant')
    expect(ProgramMembership.where(program_id: program.id, user_id: user.id).count).to eq(1)
  end

  it 'does not consume an invitation or create an account when registration is invalid' do
    invitation = create_participant_invitation(create_program, create_user(roles: ['system_admin']))
    attributes = user_attributes(password: 'short', password_confirmation: 'short')
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Password is too short')
    expect(User.where(email: attributes[:email])).to be_empty
    expect(ParticipantInvitation.available(invitation.token)).to be_present
    expect(invitation.program.memberships).to be_empty
  end

  it 'revokes pending invitations without deleting their history' do
    admin = create_user(roles: ['system_admin'])
    invitation = create_participant_invitation(create_program, admin)
    sign_in(admin)
    get program_participants_path(invitation.program)
    status = response.parsed_body.at_css('.invitation-status')
    expect(status.at_css('.status-label').text).to eq('Pending')
    expect(status.at_css('form button.secondary-action').text).to eq('Revoke')
    expect(status.at_css('form')['action']).to eq(program_participant_invitation_path(invitation.program, invitation))
    delete program_participant_invitation_path(invitation.program, invitation)
    expect(response).to redirect_to(program_participants_path(invitation.program))
    expect(invitation.reload.status).to eq('Revoked')
    expect(ParticipantInvitation.available(invitation.token)).to be_nil
    follow_redirect!
    expect(response.parsed_body.at_css('.invitation-status .status-label-danger').text).to eq('Revoked')
  end

  it 'labels accepted and expired invitations on the private session list' do
    admin = create_user(roles: ['system_admin'])
    program = create_program
    create_participant_invitation(program, admin, used_at: Time.current)
    create_participant_invitation(program, admin, expires_at: 1.minute.ago)
    sign_in(admin)
    get program_participants_path(program)
    invitations = response.parsed_body.at_xpath("//section[h2='Participant Invitations']")
    expect(invitations.at_css('.status-label-success').text).to eq('Accepted')
    expect(invitations.at_css('.status-label-neutral').text).to eq('Expired')
    expect(invitations.css('form')).to be_empty
  end
end
