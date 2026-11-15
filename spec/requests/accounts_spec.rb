# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Accounts', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 14, 17)) { example.run } }

  def remembered_sign_in(user, client: self)
    client.post(session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD, remember_me: '1' })
  end

  def cookie_expiry(name = '_posebook_session')
    cookie = Array(response.headers['Set-Cookie']).find { |value| value.start_with?("#{name}=") }
    Time.httpdate(cookie[/expires=([^;]+)/i, 1])
  end

  def restored_browser(value)
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.cookies['_posebook_remember_me'] = value
    client.get(profile_path)
    client
  end

  it 'registers the first user with system admin roles and signs them in' do
    post registration_path, params: { user: user_attributes }
    user = track_record(User.find(User::BOOTSTRAP_ID))
    follow_redirect!

    expect(user).to be_system_admin
    expect(response.body).to include('Welcome, Test Participant.', 'system admin role')
  end

  it 'renders errors without claiming the first user for invalid registration' do
    post registration_path, params: { user: user_attributes(password: 'short') }

    expect(response).to have_http_status(:unprocessable_content)
    expect(User.exists?).to be(false)
    expect(response.body).to include('Password')
  end

  it 'requires phone and gender for the first account and renders required fields' do
    get new_registration_path
    expect(response.parsed_body.at_css('input[name="user[phone]"][required]')).to be_present
    expect(response.parsed_body.at_css('select[name="user[gender]"][required]')).to be_present
    post registration_path, params: { user: user_attributes(phone: '', gender: '') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.text).to include("Phone can't be blank", "Gender can't be blank")
    expect(User.exists?).to be(false)
  end

  it 'defaults registration tagging on and requires a valid handle when selected' do
    get new_registration_path
    expect(response.parsed_body.at_css('input[type="checkbox"][name="user[instagram_tagging_allowed]"]')['checked'])
      .to be_present
    attributes = user_attributes(instagram_tagging_allowed: '1')
    post registration_path, params: { user: attributes }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.text).to include("Instagram handle can't be blank")
    post registration_path, params: { user: attributes.merge(instagram_handle: 'https://example.com/artist') }
    expect(response).to have_http_status(:unprocessable_content)
    post registration_path, params: { user: attributes.merge(instagram_handle: '@Preview.Artist') }
    registered = track_record(User.find_by(email: attributes[:email]))
    expect(response).to redirect_to(root_path)
    expect(registered).to have_attributes(instagram_tagging_allowed: true, instagram_handle: 'preview.artist')
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
    expect(response.body).to include('Welcome, Test Participant.')
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
    expect(response.body).to include('Sign In', 'Forgot your password?', 'Remember me')
    expect(response.parsed_body.at_css('input[type="checkbox"][name="remember_me"]')['checked']).to be_nil
    brand = response.parsed_body.at_css('nav a.brand')
    expect(brand['href']).to eq(root_path)
    expect(brand.text.strip).to eq('Posebook')
    expect(brand.at_css('img')['alt']).to eq('')
    expect(brand.at_css('img')['src']).to include('posebook-logo')
    favicon = response.parsed_body.at_css('link[rel="icon"]')
    expect(favicon['href']).to include('posebook-favicon')
    expect(favicon['type']).to eq('image/png')
  end

  it 'uses ordinary sessions and renews browser persistence only after explicit opt-in' do
    user = create_user
    %w[0 1].each do |remember_me|
      post session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD, remember_me: remember_me }
      expect(cookie_expiry).to eq(7.days.from_now)
      expect(cookies['_posebook_remember_me'].present?).to eq(remember_me == '1')
      travel 2.days
      get profile_path
      expect(response).to have_http_status(:ok)
      expect(cookie_expiry('_posebook_remember_me')).to eq(20.years.from_now) if remember_me == '1'
    end
  end

  it 'keeps a remembered login usable after an ordinary login expires' do
    user = create_user
    remembered = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in(user)
    remembered_sign_in(user, client: remembered)
    travel 8.days
    get profile_path
    expect(response).to redirect_to(new_session_path)
    remembered.get(profile_path)
    expect(remembered.response).to have_http_status(:ok)
  end

  it 'retains remembered expiry when a controller handles a booking validation exception' do
    user = create_user
    program = create_program
    grant_participant_access(program, user)
    remembered_sign_in(user)
    post program_bookings_path(program), params: { date: 'not-a-date' }
    expect(response).to have_http_status(:found)
    expect(cookie_expiry('_posebook_remember_me')).to eq(20.years.from_now)
  end

  it 'has no application deadline when a remembered credential is restored after decades' do
    remembered_sign_in(create_user)
    original_cookie = cookies['_posebook_remember_me']
    travel 21.years
    restored = restored_browser(original_cookie)
    expect(restored.response).to have_http_status(:ok)
  end

  it 'clears remembered login on logout and allows a later seven-day sign-in' do
    user = create_user
    remembered_sign_in(user)
    delete session_path
    expect(cookies['_posebook_remember_me']).to be_blank
    get profile_path
    expect(response).to redirect_to(new_session_path)
    sign_in(user)
    expect(cookie_expiry).to eq(7.days.from_now)
    expect(cookies['_posebook_remember_me']).to be_blank
  end

  it 'does not grant a remembered session on failed login and preserves the submitted choice' do
    user = create_user
    post session_path, params: { email: user.email, password: 'incorrect', remember_me: '1' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(cookie_expiry).to eq(7.days.from_now)
    expect(cookies['_posebook_remember_me']).to be_blank
    expect(response.parsed_body.at_css('input[type="checkbox"][name="remember_me"]')['checked']).to be_present
    get profile_path
    expect(response).to redirect_to(new_session_path)
  end

  it 'clears current-browser remember state and revokes older credentials after a password change' do
    remembered_sign_in(create_user)
    old_cookie = cookies['_posebook_remember_me']
    patch password_path, params: { user: { current_password: DatabaseHelpers::TEST_PASSWORD,
                                           password: 'a new sufficiently long password',
                                           password_confirmation: 'a new sufficiently long password' } }
    expect(response).to redirect_to(profile_path)
    expect(cookies['_posebook_remember_me']).to be_blank
    expect(cookie_expiry).to eq(7.days.from_now)
    stale = restored_browser(old_cookie)
    expect(stale.response.location).to end_with(new_session_path)
    travel 8.days
    get profile_path
    expect(response).to redirect_to(new_session_path)
  end

  it 'retains remembered login after accepting an invitation as an existing account' do
    user = create_user
    invitation = create_participant_invitation(create_program, create_user(roles: ['system_admin']))
    get invitation_path(token: invitation.token)
    remembered_sign_in(user)
    expect(response).to redirect_to(invitation_path(token: invitation.token))
    post invitation_path, params: { token: invitation.token }
    track_participant_membership(invitation.program, user)
    expect(cookie_expiry('_posebook_remember_me')).to eq(20.years.from_now)
    travel 8.days
    get profile_path
    expect(response).to have_http_status(:ok)
  end

  it 'rejects a tampered remembered credential without granting a session' do
    remembered_sign_in(create_user)
    client = restored_browser("#{cookies['_posebook_remember_me']}tampered")
    expect(client.response.location).to end_with(new_session_path)
    expect(client.cookies['_posebook_remember_me']).to be_blank
  end

  it 'remembers the new account when switching away from an already remembered account' do
    remembered_sign_in(create_user(name: 'First Participant'))
    remembered_sign_in(create_user(name: 'Second Participant'))
    cookies.delete('_posebook_session')
    get profile_path
    expect(response.body).to include('Second Participant')
    expect(response.body).not_to include('First Participant')
  end

  it 'clears current-browser remember state and revokes older credentials after email confirmation' do
    user = create_user
    remembered_sign_in(user)
    old_cookie = cookies['_posebook_remember_me']
    patch profile_path, params: { user: { name: user.name, email: 'changed@example.test',
                                          current_password: DatabaseHelpers::TEST_PASSWORD } }
    token = ActionMailer::Base.deliveries.last.body.decoded[/email_change\?token=([A-Za-z0-9_-]+)/, 1]
    patch email_change_path, params: { token: token }
    expect(response).to redirect_to(new_session_path)
    expect(cookies['_posebook_remember_me']).to be_blank
    stale = restored_browser(old_cookie)
    expect(stale.response.location).to end_with(new_session_path)
  end

  it 'protects remembered credentials with HTTP-only same-site cookies secured over HTTPS' do
    https!
    remembered_sign_in(create_user)
    header = Array(response.headers['Set-Cookie']).find { |value| value.start_with?('_posebook_remember_me=') }
    expect(header.downcase).to include('httponly', 'samesite=lax', 'secure')
  end
end
