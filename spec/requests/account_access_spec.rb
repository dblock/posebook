# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Account access management', :aggregate_failures, :database, type: :request do
  it 'lets a user deactivate their account without deleting it or permitting recovery' do
    user = create_user
    sign_in(user)
    token = reset_token(user)
    post account_deactivation_path, params: { current_password: DatabaseHelpers::TEST_PASSWORD }
    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(response.body).to include('Your account has been deactivated.')
    expect(User.find(user.id)).not_to be_active
    expect(User.for_password_reset(token)).to be_nil
    post session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD }
    expect(response).to have_http_status(:unprocessable_content)
    ActionMailer::Base.deliveries.clear
    post password_resets_path, params: { email: user.email }
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'requires a correct password for self-deactivation' do
    user = create_user
    sign_in(user)
    post account_deactivation_path, params: { current_password: 'incorrect' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.css('main form').pluck('id')).to eq(['deactivation-form'])
    expect(user.reload).to be_active
  end

  it 'protects system admin accounts from deactivation' do
    user = create_user(roles: ['system_admin'])
    sign_in(user)
    get new_account_deactivation_path
    expect(response.body).to include('System admin accounts stay active')
    expect(response.parsed_body.css('main form')).to be_empty
    post account_deactivation_path, params: { current_password: DatabaseHelpers::TEST_PASSWORD }
    expect(response).to have_http_status(:unprocessable_content)
    patch admin_user_path(user), params: { active: false }
    expect(user.reload).to be_active
  end

  it 'restricts user administration to the system admin role' do
    user = create_user
    sign_in(user)
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
    patch admin_user_path(user), params: { active: false }
    expect(response).to have_http_status(:forbidden)
    expect(user.reload).to be_active
  end

  it 'lets a system admin deactivate and reactivate accounts while preserving their roles' do
    admin = create_user(roles: ['system_admin'])
    user = create_user
    client = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in(user, client: client)
    sign_in(admin)
    get admin_users_path
    expect(response.body).to include(user.email, 'Deactivate')
    patch admin_user_path(user), params: { active: false }
    client.get(root_path)
    expect(client.response.location).to end_with(new_session_path)
    patch admin_user_path(user), params: { active: true }
    expect(user.reload).to be_active
    expect(user.roles).to eq([])
    sign_in(user, client: client)
    client.get(root_path)
    expect(client.response).to have_http_status(:ok)
  end
end
