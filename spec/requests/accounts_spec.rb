# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Accounts', :aggregate_failures, :database, type: :request do
  it 'registers the first user with system admin roles and signs them in' do
    post registration_path, params: { user: user_attributes }
    user = track_record(User.find(User::BOOTSTRAP_ID))
    follow_redirect!

    expect(user).to be_system_admin
    expect(response.body).to include('Welcome, Test Artist.', 'system admin role')
  end

  it 'renders errors without claiming the first user for invalid registration' do
    post registration_path, params: { user: user_attributes(password: 'short') }

    expect(response).to have_http_status(:unprocessable_content)
    expect(User.exists?).to be(false)
    expect(response.body).to include('Password')
  end

  it 'closes both registration endpoints after the first account exists' do
    create_user
    get new_registration_path
    expect(response).to redirect_to(new_session_path)
    post registration_path, params: { user: user_attributes }
    expect(response).to redirect_to(new_session_path)
    expect(User.count).to eq(1)
  end

  it 'supports normalized-email login and logout' do
    user = create_user
    post session_path, params: { email: " #{user.email.upcase} ", password: DatabaseHelpers::TEST_PASSWORD }
    follow_redirect!
    expect(response.body).to include('Welcome, Test Artist.')
    delete session_path
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it 'uses the same login error for unknown emails and incorrect passwords' do
    user = create_user
    [user.email, 'missing@example.test'].each do |email|
      post session_path, params: { email: email, password: 'incorrect' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Invalid email or password.')
    end
  end

  it 'renders the sign-in form' do
    get new_session_path
    expect(response.body).to include('Sign In', 'Forgot your password?')
  end
end
