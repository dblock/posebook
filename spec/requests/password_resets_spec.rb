# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Password recovery', :aggregate_failures, :database, type: :request do
  it 'renders a recovery form' do
    get new_password_reset_path
    expect(response.body).to include('Reset Your Password')
  end

  it 'emails a reset link without revealing whether an account exists' do
    user = create_user
    post password_resets_path, params: { email: user.email.upcase }
    notice = flash[:notice]
    expect(ActionMailer::Base.deliveries).to be_empty
    deliver_emails
    mail = ActionMailer::Base.deliveries.last
    post password_resets_path, params: { email: 'missing@example.test' }

    expect(flash[:notice]).to eq(notice)
    expect(ActionMailer::Base.deliveries.length).to eq(1)
    expect(mail.to).to eq([user.email])
    expect(mail.body.decoded).to include('http://example.com/password_resets/', '30 minutes')
  end

  it 'resets a password, rejects replay, and invalidates all existing sessions' do
    user = create_user
    other_client = ActionDispatch::Integration::Session.new(Rails.application)
    other_client.post(session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD,
                                              remember_me: '1' })
    token = reset_token(user)
    patch password_reset_path(token), params: { user: { password: 'a new sufficiently long password',
                                                        password_confirmation: 'a new sufficiently long password' } }
    expect(response).to redirect_to(new_session_path)
    other_client.get(root_path)
    expect(other_client.response).to redirect_to(new_session_path)
    get edit_password_reset_path(token)
    expect(response).to redirect_to(new_password_reset_path)
    expect(user.reload.authenticate('a new sufficiently long password')).to eq(user)
  end

  it 'shows an error and preserves the reset link after invalid password input' do
    user = create_user
    token = reset_token(user)
    patch password_reset_path(token), params: { user: { password: 'short', password_confirmation: 'short' } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(User.for_password_reset(token)).to eq(user)
    expect(user.reload.authenticate(DatabaseHelpers::TEST_PASSWORD)).to eq(user)
  end

  it 'rejects expired links and renders valid links without consuming them' do
    user = create_user
    token = reset_token(user)
    get edit_password_reset_path(token)
    expect(response.body).to include('Choose a New Password')
    user.set(password_reset_expires_at: 1.minute.ago)
    get edit_password_reset_path(token)
    expect(response).to redirect_to(new_password_reset_path)
  end

  it 'reports unavailable email configuration without claiming that mail was sent' do
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post password_resets_path, params: { email: 'missing@example.test' }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('not configured')
  end

  it 'rolls back the reset challenge when email cannot be queued' do
    user = create_user
    error = ActiveJob::EnqueueError.new('Unavailable')
    allow(EmailDeliveryJob).to receive(:perform_later).and_raise(error)
    allow(NewRelic::Agent).to receive(:notice_error)
    post password_resets_path, params: { email: user.email }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('could not be queued')
    expect(user.reload.password_reset_digest).to be_nil
    expect(EmailDelivery.where(resource_id: user.id)).to be_empty
    expect(NewRelic::Agent).to have_received(:notice_error).with(an_instance_of(EmailDelivery::Unavailable)).once
  end
end
