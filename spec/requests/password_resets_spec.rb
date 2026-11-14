# frozen_string_literal: true

require 'rails_helper'
require 'net/smtp'

RSpec.describe 'Password recovery', :aggregate_failures, :database, type: :request do
  it 'renders a recovery form' do
    get new_password_reset_path
    expect(response.body).to include('Reset Your Password')
  end

  it 'emails a reset link without revealing whether an account exists' do
    user = create_user
    post password_resets_path, params: { email: user.email.upcase }
    notice = flash[:notice]
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
    sign_in(user, client: other_client)
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

  it 'reports delivery failures without sending real email' do
    user = create_user
    allow(PasswordResetMailer).to receive(:reset).and_raise(Net::SMTPAuthenticationError, 'Unavailable')
    post password_resets_path, params: { email: user.email }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('could not be sent')
  end
end
