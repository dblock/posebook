# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinator invitations', :aggregate_failures, :database, type: :request do
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:venue) { create_venue }
  let(:program) { create_program(venue: venue, program_label: 'Workshop') }

  def created_link
    follow_redirect!
    response.parsed_body.at_css('#invitation_link')['value']
  end

  def register_recipient(invitation)
    post coordinator_invited_registration_path,
         params: { token: invitation.token, user: user_attributes(email: invitation.email, roles: ['system_admin']) }
    track_record(User.find_by(email: invitation.email))
  end

  it 'offers an explicit venue promotion for a registered email without duplicating accounts' do
    user = create_user
    sign_in(admin)
    post venue_coordinators_path(venue), params: { email: " #{user.email.upcase} ", send_email: '1' }
    expect(response.body).to include('This Email Is Already Registered', 'Grant Venue Coordinator Access')
    expect(VenueMembership.where(venue_id: venue.id, user_id: user.id)).to be_empty
    expect(CoordinatorInvitation.where(venue_id: venue.id)).to be_empty
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'promotes an existing venue participant while retaining the account and participant membership' do
    user = create_user
    participant = grant_participant_access(program, user)
    sign_in(admin)
    post venue_coordinators_path(venue), params: { email: user.email, grant_access: '1', roles: ['system_admin'] }
    membership = track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
    expect(membership.roles).to eq(['venue_coordinator'])
    expect(program.managed_by?(user)).to be(true)
    expect(user.reload.roles).to be_empty
    expect(participant.reload.roles).to eq(['participant'])
  end

  it 'lets a venue manager promote a participant without changing their booking grant or other roles' do
    manager = create_user
    grant_venue_access(venue, manager)
    user = create_user
    membership = grant_participant_access(program, user)
    invited_at = membership.booking_invited_at
    sign_in(manager)
    post program_coordinators_path(program), params: { email: user.email }
    expect(response.body).to include('Grant Workshop Coordinator Access')
    expect(membership.reload.roles).to eq(['participant'])
    post program_coordinators_path(program), params: { email: user.email, grant_access: '1' }
    expect(membership.reload.roles).to contain_exactly('participant', 'program_coordinator')
    expect(membership.booking_invited_at).to eq(invited_at)
    expect(venue.coordinated_by?(user)).to be(false)
    expect(create_program(venue: venue).managed_by?(user)).to be(false)
  end

  it 'emails an invitation restricted to the requested venue and address' do
    sign_in(admin)
    post venue_coordinators_path(venue), params: { name: 'Invited Manager', email: 'manager@example.test',
                                                   send_email: '1', program_id: create_program.id }
    invitation = track_record(CoordinatorInvitation.find_by(venue_id: venue.id))
    created_link
    expect(invitation.program_id).to be_nil
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(['manager@example.test'])
    expect(mail.subject).to include('Venue Coordinator', venue.name)
    expect(mail.body.decoded).to include('/coordinator_invitation?token=', 'manager@example.test')
  end

  it 'only displays a newly created coordinator link once on its private management page' do
    sign_in(admin)
    post venue_coordinators_path(venue), params: { email: 'manager@example.test' }
    invitation = track_record(CoordinatorInvitation.find_by(venue_id: venue.id))
    link = created_link
    token = URI.decode_www_form(URI(link).query).to_h.fetch('token')
    expect(CoordinatorInvitation.available(token)).to eq(invitation)
    expect(invitation.attributes.values).not_to include(token)
    get venue_coordinator_invitation_path(venue, invitation)
    expect(response.parsed_body.at_css('#invitation_link')).to be_nil
  end

  it 'fills in the invited name and read-only email without consuming the link on GET' do
    invitation = create_coordinator_invitation(venue, admin, name: 'Invited Manager')
    get coordinator_invitation_path(token: invitation.token)
    expect(response.parsed_body.at_css('#user_email')['readonly']).to be_present
    expect(response.parsed_body.at_css('#user_name')['value']).to eq('Invited Manager')
    expect(invitation.reload.used_at).to be_nil
  end

  it 'registers a venue coordinator with inherited venue access but no global role' do
    invitation = create_coordinator_invitation(venue, admin)
    user = register_recipient(invitation)
    track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
    expect(response).to redirect_to(venue_path(venue))
    expect(user.roles).to be_empty
    expect(program.managed_by?(user)).to be(true)
    expect(create_program.managed_by?(user)).to be(false)
    expect(invitation.reload.used_by_id).to eq(user.id)
    post coordinator_invitation_path, params: { token: invitation.token }
    expect(response).to have_http_status(:gone)
  end

  it 'allows a venue manager to create a manual session invitation with email delivery disabled' do
    manager = create_user
    grant_venue_access(venue, manager)
    sign_in(manager)
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post program_coordinators_path(program), params: { email: 'teacher@example.test' }
    invitation = track_record(CoordinatorInvitation.find_by(program_id: program.id))
    link = created_link
    expect(response.body).to include('Workshop Coordinator')
    expect(link).to include('/coordinator_invitation?token=')
    expect(invitation.invited_by).to eq(manager)
  end

  it 'creates venue and session links without email or SMTP even when email delivery is checked' do
    sign_in(admin)
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    [venue_coordinators_path(venue), program_coordinators_path(program)].each do |path|
      post path, params: { name: 'Invited Manager', send_email: '1' }
      link = created_link
      token = URI.decode_www_form(URI(link).query).to_h.fetch('token')
      invitation = track_record(CoordinatorInvitation.available(token))
      expect(invitation.email).to be_nil
      expect(response.body).to include('No email restriction.')
    end
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'registers a session coordinator without granting parent, sibling, or participant access' do
    invitation = create_coordinator_invitation(program, admin)
    user = register_recipient(invitation)
    membership = track_participant_membership(program, user)
    expect(response).to redirect_to(program_path(program))
    expect(membership.roles).to eq(['program_coordinator'])
    expect(membership.booking_invited_at).to be_nil
    expect(venue.coordinated_by?(user)).to be(false)
    expect(create_program(venue: venue).managed_by?(user)).to be(false)
  end

  it 'blocks account creation using an email different from the invited address' do
    recipient = create_user
    invitation = create_coordinator_invitation(program, admin, email: recipient.email)
    wrong_attributes = user_attributes
    post coordinator_invited_registration_path, params: { token: invitation.token, user: wrong_attributes }
    expect(response).to have_http_status(:unprocessable_content)
    expect(User.where(email: wrong_attributes[:email])).to be_empty
    expect(invitation.reload.used_at).to be_nil
  end

  it 'prevents the wrong signed-in account from accepting a forwarded coordinator link' do
    invitation = create_coordinator_invitation(program, admin)
    wrong_user = create_user
    sign_in(wrong_user)
    get coordinator_invitation_path(token: invitation.token)
    expect(response.body).to include('Sign Out and Use the Invited Account')
    expect(response.body).not_to include('Accept Workshop Coordinator Invitation')
    post coordinator_invitation_path, params: { token: invitation.token }
    expect(response).to have_http_status(:forbidden)
    expect(invitation.reload.used_at).to be_nil
  end

  it 'returns the invited existing account to the link after switching login' do
    recipient = create_user
    invitation = create_coordinator_invitation(program, admin, email: recipient.email)
    sign_in(create_user)
    get coordinator_invitation_path(token: invitation.token)
    delete session_path, params: { coordinator_invitation_token: invitation.token }
    expect(response).to redirect_to(coordinator_invitation_path(token: invitation.token))
    follow_redirect!
    sign_in(recipient)
    expect(response).to redirect_to(coordinator_invitation_path(token: invitation.token))
    post coordinator_invitation_path, params: { token: invitation.token }
    track_participant_membership(program, recipient)
    expect(response).to redirect_to(program_path(program))
    expect(invitation.reload.used_by_id).to eq(recipient.id)
  end

  it 'preserves the invitation when registration fails validation' do
    invitation = create_coordinator_invitation(venue, admin)
    post coordinator_invited_registration_path,
         params: { token: invitation.token,
                   user: user_attributes(email: invitation.email, password: 'short', password_confirmation: 'short') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Password is too short')
    expect(invitation.reload.used_at).to be_nil
    expect(User.where(email: invitation.email)).to be_empty
    expect(VenueMembership.where(venue_id: venue.id)).to be_empty
  end

  it 'denies venue role invitations by venue managers and invitations at other venues' do
    manager = create_user
    grant_venue_access(venue, manager)
    sign_in(manager)
    post venue_coordinators_path(venue), params: { email: 'forbidden@example.test' }
    expect(response).to have_http_status(:forbidden)
    post program_coordinators_path(create_program), params: { email: 'forbidden@example.test' }
    expect(response).to have_http_status(:forbidden)
    expect(CoordinatorInvitation.where(email: 'forbidden@example.test')).to be_empty
  end

  it 'denies peer delegation by session coordinators' do
    organizer = create_user
    grant_coordinator_access(program, organizer)
    sign_in(organizer)
    post program_coordinators_path(program), params: { email: 'forbidden@example.test' }
    expect(response).to have_http_status(:forbidden)
    expect(CoordinatorInvitation.where(email: 'forbidden@example.test')).to be_empty
  end

  it 'keeps coordinator invitation history private and revocation scoped without deleting records' do
    invitation = create_coordinator_invitation(program, admin)
    sign_in(create_user)
    get program_coordinator_invitation_path(program, invitation)
    expect(response).to have_http_status(:forbidden)
    sign_in(admin)
    delete program_coordinator_invitation_path(create_program, invitation)
    expect(response).to have_http_status(:not_found)
    delete program_coordinator_invitation_path(program, invitation)
    expect(response).to redirect_to(program_coordinators_path(program))
    expect(invitation.reload.status).to eq('Revoked')
    follow_redirect!
    expect(response.body).to include(invitation.email, 'Revoked')
    get coordinator_invitation_path(token: invitation.token)
    expect(response).to have_http_status(:gone)
    get coordinator_invitation_path(token: 'invalid')
    expect(response).to have_http_status(:gone)
  end

  it 'makes outstanding invitations unavailable after the sender loses management authority' do
    manager = create_user
    membership = grant_venue_access(venue, manager)
    invitation = create_coordinator_invitation(program, manager)
    membership.revoke_coordinator_access
    get coordinator_invitation_path(token: invitation.token)
    expect(response).to have_http_status(:gone)
    expect(invitation.reload.used_at).to be_nil
  end

  it 'makes an outstanding venue invitation unavailable when its admin sender becomes inactive' do
    venue_invitation = create_coordinator_invitation(venue, admin)
    admin.update!(active: false)
    get coordinator_invitation_path(token: venue_invitation.token)
    expect(response).to have_http_status(:gone)
    expect(venue_invitation.reload.used_at).to be_nil
  end

  it 'rejects inactive registered accounts, invalid emails, and stale promotion confirmations' do
    user = create_user(active: false)
    sign_in(admin)
    [user.email, 'invalid'].each do |email|
      post venue_coordinators_path(venue), params: { email: email, grant_access: '1' }
      expect(response).to have_http_status(:unprocessable_content)
    end
    post venue_coordinators_path(venue), params: { email: 'unregistered@example.test', grant_access: '1' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(CoordinatorInvitation.where(venue_id: venue.id)).to be_empty
    expect(VenueMembership.where(venue_id: venue.id)).to be_empty
  end

  it 'rejects unavailable email delivery but keeps a shareable link after delivery failure' do
    sign_in(admin)
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post venue_coordinators_path(venue), params: { email: 'mail@example.test', send_email: '1' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(CoordinatorInvitation.where(venue_id: venue.id)).to be_empty
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(true)
    allow(CoordinatorInvitationMailer).to receive(:invite).and_raise(IOError, 'Unavailable')
    allow(NewRelic::Agent).to receive(:notice_error)
    post venue_coordinators_path(venue), params: { email: 'mail@example.test', send_email: '1' }
    track_record(CoordinatorInvitation.find_by(venue_id: venue.id))
    created_link
    expect(response.body).to include('Email delivery failed.')
    expect(NewRelic::Agent).to have_received(:notice_error).once
  end
end
