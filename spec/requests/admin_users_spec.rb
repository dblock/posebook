# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Administrator user editing', :aggregate_failures, :database, type: :request do
  def update_user(user, **attributes)
    patch admin_user_path(user), params: { user: { name: user.name, email: user.email, phone: user.phone }
                                                .merge(attributes) }
  end

  it 'requires authentication before reading or editing user information' do
    user = create_user
    get edit_admin_user_path(user)
    expect(response).to redirect_to(new_session_path)
    update_user(user, name: 'Forbidden')
    expect(response).to redirect_to(new_session_path)
    expect(user.reload.name).not_to eq('Forbidden')
  end

  it 'saves contact information without granting privileges or changing passwords or access' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    version = user.session_version
    get admin_users_path
    expect(response.parsed_body.at_css("a[href='#{edit_admin_user_path(user)}']")).to be_present
    get edit_admin_user_path(user)
    expect(response.parsed_body.css('main input[type=password]')).to be_empty
    update_user(user, name: 'Edited Artist', email: " #{user.email.upcase} ", phone: '+12125551234',
                      roles: ['system_admin'], active: false, password: 'a forbidden password change')
    expect(response).to redirect_to(admin_users_path)
    follow_redirect!
    expect(response.body).to include('User information saved.', 'Edited Artist', '+12125551234')
    expect(user.reload).to have_attributes(name: 'Edited Artist', phone: '+12125551234', roles: [],
                                           active: true, session_version: version)
    expect(user.authenticate(DatabaseHelpers::TEST_PASSWORD)).to eq(user)
  end

  it 'changes email immediately and revokes sessions, recovery, pending changes, and verification' do
    user = create_user(email_verified_at: Time.current, pending_email: 'pending@example.test',
                       email_change_digest: 'an outstanding challenge', email_change_expires_at: 30.minutes.from_now)
    client = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in(user, client: client)
    token = reset_token(user)
    sign_in(create_user(roles: ['system_admin']))
    ActionMailer::Base.deliveries.clear
    update_user(user, email: ' New-Address@Example.Test ')
    expect(response).to redirect_to(admin_users_path)
    expect(user.reload).to have_attributes(email: 'new-address@example.test', email_verified_at: nil,
                                           pending_email: nil, email_change_digest: nil, email_change_expires_at: nil)
    expect(User.for_password_reset(token)).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
    client.get(root_path)
    expect(client.response.location).to end_with(new_session_path)
    client.post(session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD })
    expect(client.response.location).to end_with(root_path)
  end

  it 'allows public profile edits but never accepts administrator-supplied tagging consent' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    get edit_admin_user_path(user)
    expect(response.parsed_body.css('input[name="user[instagram_tagging_allowed]"]')).to be_empty
    update_user(user, display_name: 'Alex Artist', instagram_url: '@Alex.Artist', instagram_tagging_allowed: '1')
    expect(response).to redirect_to(admin_users_path)
    expect(user.reload.public_name).to eq('Alex Artist')
    expect(user.instagram_url).to eq('https://www.instagram.com/alex.artist/')
    expect(user.public_instagram_url).to be_nil
  end

  it 'preserves consent for equivalent links and revokes it when an administrator changes the account' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user(instagram_url: '@Artist.Model', instagram_tagging_allowed: true)
    update_user(user, name: 'Updated Artist', instagram_url: 'instagram.com/ARTIST.MODEL')
    expect(user.reload.public_instagram_username).to eq('artist.model')
    update_user(user, instagram_url: '@Another.Artist', instagram_tagging_allowed: '1')
    expect(user.reload.instagram_url).to eq('https://www.instagram.com/another.artist/')
    expect(user.public_instagram_url).to be_nil
    expect(user.history_tracks.last.modified).to include('instagram_tagging_allowed' => false)
  end

  it 'keeps invalid edits on their form without changing persisted information' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    original = user.reload.attributes
    update_user(user, name: 'Invalid Edit', phone: '123', email: 'changed@example.test')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css('main h1').text).to eq('Edit User')
    expect(response.body).to include('Phone is invalid', 'Invalid Edit')
    expect(user.reload.attributes).to eq(original)
  end

  it 'rejects an email address belonging to another user' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    other = create_user
    update_user(user, email: other.email)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Email has already been taken')
    expect(user.reload.email).not_to eq(other.email)
  end

  it 'handles a competing email claim at the unique database index' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    other = create_user
    allow(User).to receive(:find).with(user.id.to_s).and_return(user)
    allow(user).to receive(:valid?).and_wrap_original do |validation, *arguments|
      result = validation.call(*arguments)
      other.set(email: 'raced@example.test')
      result
    end
    update_user(user, email: 'raced@example.test')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Email has already been taken')
    expect(user.reload.email).not_to eq('raced@example.test')
  end

  it 'edits inactive users without reactivating them or dropping pending email changes' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user(active: false, pending_email: 'pending@example.test', email_change_digest: 'pending')
    update_user(user, name: 'Updated Inactive Artist')
    expect(response).to redirect_to(admin_users_path)
    expect(user.reload).to have_attributes(name: 'Updated Inactive Artist', active: false,
                                           pending_email: 'pending@example.test', email_change_digest: 'pending')
  end

  it 'signs an administrator out with confirmation after changing their own email' do
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    update_user(admin, email: 'updated-admin@example.test')
    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(response.body).to include('User information saved. Your email changed; sign in again.')
    sign_in(admin.reload)
    get admin_users_path
    expect(response).to have_http_status(:ok)
  end

  it 'rejects missing edits and invalid access values without deactivating the user' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    [{}, { active: 'invalid' }].each do |attributes|
      patch admin_user_path(user), params: attributes
      expect(response).to have_http_status(:bad_request)
      expect(user.reload).to be_active
    end
  end
end
