# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Participant invitations', :aggregate_failures, :database, type: :request do
  def invitation_token
    URI.decode_www_form(URI(response.parsed_body.at_css('#invitation_link')['value']).query).to_h.fetch('token')
  end

  it 'formats invitation recipients from their available details without exposing matching accounts' do
    admin = create_user(roles: ['system_admin'])
    program = create_program
    unknown = create_user(name: 'Private account name', gender: 'female')
    recipients = [{ name: 'Drawing <Model> & Artist', email: 'artist@example.test' },
                  { email: unknown.email }, { name: 'Named guest' }, {}]
    recipients.each { |attributes| create_participant_invitation(program, admin, **attributes) }
    sign_in(admin)
    get program_participant_invitations_path(program)
    expect(response.parsed_body.css('.invitation-recipient').map(&:text))
      .to contain_exactly('Drawing <Model> & Artist <artist@example.test>', unknown.email, 'Named guest',
                          'Personal invitation')
    expect(response.body).not_to include(unknown.name, '(Female)')
  end

  it 'shows invitation dates, sender, status, and compact actions in a separate labeled table' do
    admin = create_user(name: 'Invitation Sender', roles: ['system_admin'])
    program = create_program(participant_label: 'Model', time_zone: 'America/Los_Angeles')
    invitation = create_participant_invitation(program, admin, name: 'Invited Model', email: 'model@example.test',
                                                               created_at: Time.utc(2026, 11, 14, 2, 30),
                                                               used_at: Time.utc(2026, 11, 14, 3, 30))
    sign_in(admin)
    get program_participant_invitations_path(program)
    row = response.parsed_body.at_css("[data-invitation='#{invitation.id}']")
    expect(response.parsed_body.at_css('.program-tabs [aria-current="page"]').text).to eq('Invitations')
    expect(row.text).to include('Invited Model <model@example.test>', admin.name, 'Accepted')
    expect(row.css('time').pluck('datetime'))
      .to eq([invitation.created_at, invitation.expires_at, invitation.used_at]
               .map { |time| time.in_time_zone(program.time_zone).iso8601 })
    expect(row.at_css('a.button-link')['href']).to eq(program_participant_invitation_path(program, invitation))
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.body).not_to include(invitation.token, invitation.token_digest)
  end

  it 'keeps invitation details off the roster and creation, viewing, and canceling under the new tab' do
    admin = create_user(roles: ['system_admin'])
    invitation = create_participant_invitation(create_program, admin, email: 'not-on-the-roster@example.test')
    program = invitation.program
    sign_in(admin)
    get program_participants_path(program)
    expect(response.body).not_to include(invitation.email, 'Create Invitation')
    [new_program_participant_invitation_path(program),
     program_participant_invitation_path(program, invitation)].each do |path|
      get path
      expect(response.parsed_body.at_css('.program-tabs [aria-current="page"]').text).to eq('Invitations')
      expect(response.parsed_body.css('main a').pluck('href')).to include(program_participant_invitations_path(program))
    end
    expect(response.parsed_body.at_css('.invitation-recipient').text).to eq(invitation.email)
  end

  it 'limits the invitation table to the requested program and authorized managers' do
    program = create_program
    coordinator = create_user
    grant_coordinator_access(program, coordinator)
    create_participant_invitation(program, coordinator, email: 'scoped@example.test')
    create_participant_invitation(create_program, coordinator, email: 'foreign@example.test')
    get program_participant_invitations_path(program)
    expect(response).to redirect_to(new_session_path)
    sign_in(coordinator)
    get program_participant_invitations_path(program)
    expect(response.body).to include('scoped@example.test')
    expect(response.body).not_to include('foreign@example.test')
    sign_in(create_user)
    get program_participant_invitations_path(program)
    expect(response).to have_http_status(:not_found)
  end

  it 'includes inherited venue coordinators but excludes ordinary participants from invitation history' do
    program = create_program
    coordinator = create_user
    grant_venue_access(program.venue, coordinator)
    sign_in(coordinator)
    get program_participant_invitations_path(program)
    expect(response.body).to include('No invitations.')
    expect(response.parsed_body.at_css('.participant-pagination')).to be_nil
    participant = create_user
    grant_participant_access(program, participant)
    sign_in(participant)
    get program_participant_invitations_path(program)
    expect(response).to have_http_status(:not_found)
    get program_path(program)
    expect(response.parsed_body.css('.program-tabs a').map(&:text)).not_to include('Invitations')
  end

  it 'paginates tied invitation dates stably without losing older history' do
    admin = create_user(roles: ['system_admin'])
    program = create_program
    invitations = Array.new(51) { create_participant_invitation(program, admin, created_at: Time.utc(2026, 11, 14)) }
    sign_in(admin)
    get program_participant_invitations_path(program)
    first = response.parsed_body.css('tbody tr').pluck('data-invitation')
    expect(first).to eq(invitations.reverse.first(50).map { |invitation| invitation.id.to_s })
    expect(response.parsed_body.at_css('a[rel="next"]')['href'])
      .to eq(program_participant_invitations_path(program, page: 2))
    get program_participant_invitations_path(program, page: 2)
    expect(response.parsed_body.css('tbody tr').pluck('data-invitation')).to eq([invitations.first.id.to_s])
    expect(response.parsed_body.at_css('a[rel="prev"]')['href'])
      .to eq(program_participant_invitations_path(program, page: 1))
    expect(response.parsed_body.at_css('a[rel="next"]')).to be_nil
  end

  it 'normalizes invalid page inputs, retains empty pages, and returns revocations to their page' do
    admin = create_user(roles: ['system_admin'])
    program = create_program
    invitation = create_participant_invitation(program, admin)
    sign_in(admin)
    [-1, 'invalid'].each do |page|
      get program_participant_invitations_path(program, page: page)
      expect(response.parsed_body.css('tbody tr').length).to eq(1)
    end
    get program_participant_invitations_path(program, page: 999)
    expect(response.body).to include('No invitations on this page.')
    delete program_participant_invitation_path(program, invitation, page: 2)
    expect(response).to redirect_to(program_participant_invitations_path(program, page: 2))
    expect(invitation.reload.status).to eq('Revoked')
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

  it 'sends invitation email when an address is given using the configured mail host' do
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    program = create_program(start_time: '19:15', available_weekdays: ['2'],
                             time_zone: 'America/Los_Angeles')
    post program_participant_invitations_path(program),
         params: { participant_invitation: { email: 'participant@example.test' } }
    track_record(program.participant_invitations.first)
    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_nil
    deliver_emails
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(['participant@example.test'])
    expect(mail.body.decoded).to include('http://example.com/invitation?token=',
                                         'Tuesday at 7:15 PM (America/Los_Angeles)', 'using participant@example.test')
  end

  it 'creates a link without email or SMTP' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post program_participant_invitations_path(program),
         params: { participant_invitation: { name: 'Invited Artist' } }
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
         params: { participant_invitation: { email: 'participant@example.test' } }
    track_record(program.participant_invitations.first)
    follow_redirect!
    expect(response.body).to include('Email could not be queued.')
    expect(response.parsed_body.at_css('#invitation_link')).to be_present
    expect(NewRelic::Agent).to have_received(:notice_error).with(an_instance_of(EmailDelivery::Unavailable)).once
  end

  it 'rejects invalid addresses and still creates links when delivery is unavailable' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    post program_participant_invitations_path(program), params: { participant_invitation: { email: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(program.participant_invitations).to be_empty
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post program_participant_invitations_path(program),
         params: { participant_invitation: { email: 'a@example.test' } }
    invitation = track_record(program.participant_invitations.first)
    expect(invitation.email).to eq('a@example.test')
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
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

  it 'retains a signed-in invitation for retry when coordinator notifications cannot queue' do
    program = create_program
    coordinator = create_user
    grant_coordinator_access(program, coordinator)
    invitation = create_participant_invitation(program, coordinator)
    user = create_user
    sign_in(user)
    allow(EmailDeliveryJob).to receive(:perform_later).and_return(false)
    post invitation_path, params: { token: invitation.token }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('The invitation was not accepted', 'Accept Invitation')
    expect(invitation.reload.used_at).to be_nil
    expect(program.participant?(user)).to be(false)
    allow(EmailDeliveryJob).to receive(:perform_later).and_call_original
    post invitation_path, params: { token: invitation.token }
    track_participant_membership(program, user)
    expect(response).to redirect_to(program_path(program, section: 'calendar'))
  end

  it 'rolls back invited registration on notification failure and retains a working registration form' do
    program = create_program
    coordinator = create_user
    grant_coordinator_access(program, coordinator)
    invitation = create_participant_invitation(program, coordinator)
    attributes = user_attributes(name: 'Retained Applicant', instagram_tagging_allowed: '0')
    allow(EmailDeliveryJob).to receive(:perform_later).and_return(false)
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.at_css('#user_name')['value']).to eq('Retained Applicant')
    expect(response.parsed_body.at_css('form[action="/invitation/register"] input[name="_method"]')).to be_nil
    expect(User.where(email: attributes[:email])).not_to exist
    expect(invitation.reload.used_at).to be_nil
    allow(EmailDeliveryJob).to receive(:perform_later).and_call_original
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    user = track_record(User.find_by(email: attributes[:email]))
    track_participant_membership(program, user)
    expect(response).to redirect_to(program_path(program, section: 'calendar'))
  end

  it 'revokes pending invitations without deleting their history' do
    admin = create_user(roles: ['system_admin'])
    invitation = create_participant_invitation(create_program, admin)
    sign_in(admin)
    get program_participant_invitations_path(invitation.program)
    row = response.parsed_body.at_css("[data-invitation='#{invitation.id}']")
    status = row.at_css('.invitation-status')
    expect(status.at_css('.status-label').text).to eq('Pending')
    expect(row.at_css('form button.secondary-action').text).to eq('Revoke')
    expect(row.at_css('form')['action'])
      .to eq(program_participant_invitation_path(invitation.program, invitation, page: 1))
    delete program_participant_invitation_path(invitation.program, invitation)
    expect(response).to redirect_to(program_participant_invitations_path(invitation.program))
    expect(invitation.reload.status).to eq('Revoked')
    expect(ParticipantInvitation.available(invitation.token)).to be_nil
    follow_redirect!
    expect(response.parsed_body.at_css('.invitation-status .status-label-danger').text).to eq('Revoked')
  end

  it 'labels accepted and expired invitations on the private invitation list' do
    admin = create_user(roles: ['system_admin'])
    program = create_program
    create_participant_invitation(program, admin, used_at: Time.current)
    create_participant_invitation(program, admin, expires_at: 1.minute.ago)
    sign_in(admin)
    get program_participant_invitations_path(program)
    invitations = response.parsed_body.at_css('table')
    expect(invitations.at_css('.status-label-success').text).to eq('Accepted')
    expect(invitations.at_css('.status-label-neutral').text).to eq('Expired')
    expect(invitations.css('form')).to be_empty
  end
end
