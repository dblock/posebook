# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Application account verification', :aggregate_failures, :database, type: :request do
  let(:program) { create_program(applications_enabled: true) }

  before { create_user(roles: ['system_admin']) }

  around do |example|
    previous = Rails.configuration.x.password_reset_delivery_enabled
    deliveries = ActionMailer::Base.perform_deliveries
    Rails.configuration.x.password_reset_delivery_enabled = true
    ActionMailer::Base.perform_deliveries = true
    example.run
  ensure
    Rails.configuration.x.password_reset_delivery_enabled = previous
    ActionMailer::Base.perform_deliveries = deliveries
  end

  def challenge(**attributes)
    track_record(ApplicationRegistration.create!(program: program, email: user_attributes[:email], **attributes))
  end

  def register(registration, **attributes)
    post application_registration_account_path,
         params: { token: registration.token,
                   user: user_attributes(email: registration.email, instagram_tagging_allowed: '0',
                                         public_profile_private: '1', **attributes) }
  end

  def request_link(email)
    post program_application_registration_path(program), params: { application_registration: { email: email } }
    track_record(ApplicationRegistration.where(program_id: program.id).order_by(created_at: :desc).first)
  end

  it 'queues a normalized, email-bound verification link without creating an account or membership' do
    registration = request_link('  New.Applicant@example.test ')
    expect(response).to redirect_to(new_program_application_registration_path(program))
    delivery = EmailDelivery.find_by(resource_id: registration.id)
    token = delivery.token
    expect(QueuedJob.find(delivery.queued_job_id).handler).not_to include(token)
    deliver_emails
    email = ActionMailer::Base.deliveries.last
    expect(email.to).to eq(['new.applicant@example.test'])
    expect(email.body.decoded).to include(application_verification_path(token: token))
    expect(registration.expires_at).to be_within(5.seconds).of(30.minutes.from_now)
    get application_verification_path(token: token)
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(User.where(email: registration.email)).not_to exist
    expect(registration.reload.used_at).to be_nil
    expect(program.memberships.participants).not_to exist
  end

  it 'creates only a verified ordinary account and consumes the link without approving an application' do
    registration = challenge
    register(registration, roles: ['system_admin'], active: false, program_id: program.id)
    expect(response).to redirect_to(new_program_participation_application_path(program))
    user = track_record(User.find_by(email: registration.email))
    expect(user).to have_attributes(roles: [], active: true, public_profile_private: true)
    expect(user.email_verified_at).to be_present
    expect(registration.reload.used_by_id).to eq(user.id)
    expect(program.memberships.where(user_id: user.id)).not_to exist
    expect(ParticipantApplication.where(user_id: user.id)).not_to exist
    post application_registration_account_path, params: { token: registration.token, user: user_attributes }
    expect(response).to have_http_status(:gone)
    get new_registration_path
    expect(response).to redirect_to(new_session_path)
  end

  it 'does not consume links or create accounts for forged email or invalid profile submissions' do
    registration = challenge
    register(registration, email: 'forged@example.test')
    expect(response).to have_http_status(:unprocessable_content)
    expect(User.where(email: 'forged@example.test')).not_to exist
    expect(registration.reload.used_at).to be_nil
    register(registration, phone: '', gender: '')
    expect(response).to have_http_status(:unprocessable_content)
    expect(registration.reload.used_at).to be_nil
    expect(User.where(email: registration.email)).not_to exist
  end

  it 'preserves verification through account switching without changing roles or privacy' do
    user = create_user(public_profile_private: true)
    registration = challenge(email: user.email)
    sign_in(create_user)
    get application_verification_path(token: registration.token)
    expect(response.body).to include('Sign Out and Continue')
    post application_verification_path, params: { token: registration.token }
    expect(response).to have_http_status(:forbidden)
    delete session_path(application_registration_token: registration.token)
    follow_redirect!
    sign_in(user)
    expect(response).to redirect_to(application_verification_path(token: registration.token))
    post application_verification_path, params: { token: registration.token }
    expect(response).to redirect_to(new_program_participation_application_path(program))
    expect(user.reload).to have_attributes(roles: [], public_profile_private: true)
    expect(user.email_verified_at).to be_present
    expect(program.participant?(user)).to be(false)
  end

  it 'keeps normal invitation login destinations when a different invitation replaces verification' do
    user = create_user
    registration = challenge(email: user.email)
    invitation = create_participant_invitation(program, create_user, email: user.email)
    get application_verification_path(token: registration.token)
    get invitation_path(token: invitation.token)
    sign_in(user)
    expect(response).to redirect_to(invitation_path(token: invitation.token))
    expect(user.reload.email_verified_at).to be_nil
  end

  it 'does not verify expired, used, closed-program, or inactive-venue links' do
    registration = challenge
    registration.set(expires_at: 1.second.ago)
    get application_verification_path(token: registration.token)
    expect(response).to have_http_status(:gone)
    registration = challenge
    program.update!(applications_enabled: false)
    register(registration)
    expect(response).to have_http_status(:gone)
    program.update!(applications_enabled: true)
    program.venue.update!(active: false)
    get new_program_application_registration_path(program)
    expect(response).to have_http_status(:not_found)
    expect(registration.reload.used_at).to be_nil
  end

  it 'drops obsolete queued verification emails when program intake closes before delivery' do
    request_link(user_attributes[:email])
    program.update!(applications_enabled: false)
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(EmailDelivery.where(kind: 'application_registration')).not_to exist
  end

  it 'retains a validation error if intake closes before a challenge is persisted' do
    allow(EmailDelivery).to receive(:enqueue).and_wrap_original do |original, *args, **keywords, &operation|
      program.update!(applications_enabled: false)
      original.call(*args, **keywords, &operation)
    end
    request_link(user_attributes[:email])
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('not accepting applications')
    expect(ApplicationRegistration.where(program_id: program.id)).not_to exist
  end

  it 'does not persist registration challenges when email delivery is unavailable' do
    Rails.configuration.x.password_reset_delivery_enabled = false
    request_link(user_attributes[:email])
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('could not be queued')
    expect(ApplicationRegistration.where(program_id: program.id)).not_to exist
    Rails.configuration.x.password_reset_delivery_enabled = true
    allow(EmailDeliveryJob).to receive(:perform_later).and_return(false)
    request_link(user_attributes[:email])
    expect(response).to have_http_status(:service_unavailable)
    expect(ApplicationRegistration.where(program_id: program.id)).not_to exist
  end

  it 'rolls back the new account, verification, and token consumption if transaction commit fails' do
    registration = challenge
    allow(ApplicationRegistration).to receive(:with_session).and_wrap_original do |original, &operation|
      original.call do |session|
        allow(session).to receive(:commit_transaction).and_raise(Mongo::Error::OperationFailure, 'Commit failed')
        operation.call(session)
      end
    end
    expect { register(registration) }.to raise_error(Mongo::Error::OperationFailure)
    expect(User.where(email: registration.email)).not_to exist
    expect(registration.reload.used_at).to be_nil
  end
end
