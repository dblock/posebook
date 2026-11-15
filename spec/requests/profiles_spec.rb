# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Account settings', :aggregate_failures, :database, type: :request do
  def update_profile(user, **attributes)
    patch profile_path, params: { user: { name: user.name, email: user.email, phone: user.phone }.merge(attributes) }
  end

  def confirmation_token
    deliver_emails
    ActionMailer::Base.deliveries.last.body.decoded[/email_change\?token=([A-Za-z0-9_-]+)/, 1]
  end

  it 'requires authentication for all account pages and password changes' do
    create_user
    [profile_path, history_profile_path, details_profile_path, edit_profile_path, security_profile_path,
     edit_password_path, new_account_deactivation_path].each do |path|
      get path
      expect(response).to redirect_to(new_session_path)
    end
    patch password_path, params: { user: {} }
    expect(response).to redirect_to(new_session_path)
  end

  it 'shows account information and edit links without editing forms' do
    user = create_user
    sign_in(user)
    get details_profile_path
    expect(response.body).to include(user.name, user.email, 'Not provided')
    expect(response.parsed_body.css('main form')).to be_empty
    expect(response.parsed_body.css('.profile-tabs a').pluck('href'))
      .to eq([profile_path, history_profile_path, details_profile_path, applications_profile_path,
              participant_path(user), edit_profile_path, security_profile_path])
    expect(response.parsed_body.at_css('.profile-tabs [aria-current="page"]').text).to eq('Account Details')
  end

  it 'separates account information from editing and keeps details scoped to the signed-in owner' do
    user = create_user
    other = create_user
    sign_in(user)
    get profile_path
    expect(response.parsed_body.css('.account-details')).to be_empty
    groups = response.parsed_body.css('.profile-tabs .page-tab-group')
    expect(groups.map { |group| group.css('a').map(&:text) })
      .to eq([['View', 'History', 'Account Details', 'Applications'], %w[Photos Edit Security]])
    expect(response.parsed_body.at_css('.profile-tabs .tab-separator')['aria-hidden']).to eq('true')
    get details_profile_path(user_id: other.id)
    expect(response.parsed_body.at_css('.account-details').text).to include(user.email)
    expect(response.body).not_to include(other.email)
  end

  it 'groups security forms while keeping profile editing separate and old security URLs usable' do
    sign_in(create_user)
    get edit_profile_path
    expect(response.parsed_body.css('main form').pluck('id')).to eq(['profile-form'])
    get security_profile_path
    expect(response.parsed_body.css('main form').pluck('id')).to eq(%w[password-form deactivation-form])
    expect(response.parsed_body.at_css('.profile-tabs [aria-current="page"]').text).to eq('Security')
    expect(response.parsed_body.at_css('.breadcrumbs [aria-current="page"]').text).to eq('Security')
    { edit_password_path => 'change-password',
      new_account_deactivation_path => 'deactivate-account' }.each do |path, anchor|
      get path
      expect(response).to redirect_to(security_profile_path(anchor: anchor))
    end
  end

  it 'updates name and phone without accepting privileged fields' do
    user = create_user
    sign_in(user)
    update_profile(user, name: 'Updated Participant', phone: '(212) 555-1234', roles: ['system_admin'], active: false)
    expect(response).to redirect_to(details_profile_path)
    follow_redirect!
    expect(response.body).to include('Profile saved.', 'Updated Participant', '+12125551234')
    expect(response.parsed_body.css('main form')).to be_empty
    expect(user.reload.name).to eq('Updated Participant')
    expect(user.phone).to eq('+12125551234')
    expect(user).not_to be_system_admin
    expect(user).to be_active
  end

  it 'rejects invalid profile data and does not change email without the current password' do
    user = create_user
    sign_in(user)
    update_profile(user, phone: '123')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css('main h1').text).to eq('Edit Profile')
    update_profile(user, email: 'new@example.test', current_password: 'incorrect')
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.pending_email).to be_nil
  end

  it 'requires phone and gender on profile edits' do
    user = create_user
    sign_in(user)
    get edit_profile_path
    expect(response.parsed_body.at_css('input[name="user[phone]"][required]')).to be_present
    expect(response.parsed_body.at_css('select[name="user[gender]"][required]')).to be_present
    update_profile(user, phone: '', gender: '')
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload).to have_attributes(phone: '+12025550101', gender: 'other')
  end

  it 'stores only the handle from a profile URL and keeps tagging off by default' do
    user = create_user
    sign_in(user)
    update_profile(user, display_name: '  Alex Participant  ',
                         instagram_handle: 'https://www.instagram.com/Alex.Participant/?igsh=tracking')
    expect(response).to redirect_to(details_profile_path)
    follow_redirect!
    expect(response.parsed_body.text).to include('Profile saved.', 'Alex Participant', '@alex.participant',
                                                 'Off: Instagram stays private')
    link = response.parsed_body.at_css('a[href="https://www.instagram.com/alex.participant/"]')
    expect(link['target']).to eq('_blank')
    expect(link['rel'].split).to include('noopener', 'noreferrer')
    expect(user.reload).to have_attributes(display_name: 'Alex Participant',
                                           instagram_handle: 'alex.participant')
    expect(User.collection.find(_id: user.id).first).not_to have_key('instagram_url')
    expect(user.public_name).to eq('Alex Participant')
    expect(user.public_instagram_url).to be_nil
    expect(user.public_instagram_handle).to be_nil
  end

  it 'audits tagging preferences and lets the user turn tagging off and clear their display name' do
    user = create_user
    sign_in(user)
    update_profile(user, display_name: 'Alex', instagram_handle: '@Public.Participant', instagram_tagging_allowed: '1')
    expect(user.reload.public_instagram_handle).to eq('public.participant')
    expect(user.public_instagram_url).to eq('https://www.instagram.com/public.participant/')
    expect(user.history_tracks.last.modified).to include('display_name' => 'Alex', 'instagram_tagging_allowed' => true,
                                                         'instagram_handle' => 'public.participant')
    expect(user.history_tracks.last.modifier_id).to eq(user.id)
    update_profile(user, display_name: ' ', instagram_tagging_allowed: '0')
    expect(user.reload.public_name).to eq(user.name)
    expect(user.public_instagram_url).to be_nil
    expect(user.instagram_handle).to be_present
  end

  it 'rejects invalid links, tagging without a profile, and excessively long public names without saving' do
    user = create_user
    sign_in(user)
    [{ instagram_handle: 'javascript:alert(1)' }, { instagram_tagging_allowed: '1' },
     { display_name: 'a' * 101 }].each do |attributes|
      update_profile(user, **attributes)
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload).to have_attributes(display_name: nil, instagram_handle: nil, instagram_tagging_allowed: false)
    end
  end

  it 'preserves existing opt-outs and requires a handle when enabling tagging' do
    user = create_user
    sign_in(user)
    get edit_profile_path
    checkbox = response.parsed_body.at_css('input[type="checkbox"][name="user[instagram_tagging_allowed]"]')
    expect(checkbox['checked']).to be_nil
    update_profile(user, instagram_tagging_allowed: '1', instagram_handle: '')
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload).to have_attributes(instagram_tagging_allowed: false, instagram_handle: nil)
    update_profile(user, instagram_tagging_allowed: '1', instagram_handle: '@Preview.Artist')
    expect(response).to redirect_to(details_profile_path)
    expect(user.reload.public_instagram_handle).to eq('preview.artist')
    update_profile(user, instagram_tagging_allowed: '0', instagram_handle: '')
    expect(response).to redirect_to(details_profile_path)
    expect(user.reload).to have_attributes(instagram_tagging_allowed: false, instagram_handle: nil)
  end

  it 'verifies a new email before using it for login or recovery and rejects link replay' do
    user = create_user
    old_email = user.email
    sign_in(user)
    update_profile(user, email: 'verified@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    token = confirmation_token
    follow_redirect!
    expect(response.parsed_body.text).to include('Profile saved.', old_email,
                                                 'Pending email verification for verified@example.test.')
    get email_change_path(token: token)
    expect(response.body).to include('Confirm Email Change')
    expect(user.reload.email).to eq(old_email)
    patch email_change_path, params: { token: token }
    expect(user.reload.email).to eq('verified@example.test')
    expect(user.email_verified_at).not_to be_nil
    expect(User.with_email(old_email)).to be_nil
    patch email_change_path, params: { token: token }
    expect(response).to redirect_to(new_session_path)
  end

  it 'uses a one-word pending email badge without losing the verification explanation' do
    user = create_user
    sign_in(user)
    update_profile(user, email: 'pending@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    follow_redirect!
    expect(response.parsed_body.at_css('.status-label-warning').text).to eq('Pending')
    expect(response.parsed_body.text).to include('email verification for pending@example.test.', user.email)
  end

  it 'rejects blank, malformed, and already registered email changes' do
    user = create_user
    other = create_user
    sign_in(user)
    ['', 'invalid', other.email].each do |email|
      update_profile(user, email: email, current_password: DatabaseHelpers::TEST_PASSWORD)
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'does not claim to verify an email when delivery is unavailable' do
    user = create_user
    sign_in(user)
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    update_profile(user, email: 'new@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.pending_email).to be_nil
  end

  it 'rolls back profile changes when verification email cannot be queued' do
    user = create_user
    sign_in(user)
    error = ActiveJob::EnqueueError.new('Unavailable')
    allow(EmailDeliveryJob).to receive(:perform_later).and_raise(error)
    allow(NewRelic::Agent).to receive(:notice_error)
    update_profile(user, email: 'new@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('could not be queued')
    expect(user.reload.pending_email).to be_nil
    expect(EmailDelivery.where(resource_id: user.id)).to be_empty
    expect(NewRelic::Agent).to have_received(:notice_error).with(an_instance_of(EmailDelivery::Unavailable)).once
  end

  it 'rejects expired and missing email confirmation links' do
    user = create_user
    sign_in(user)
    update_profile(user, email: 'new@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    token = confirmation_token
    user.set(email_change_expires_at: 1.minute.ago)
    get email_change_path(token: token)
    expect(response).to redirect_to(new_session_path)
    get email_change_path
    expect(response).to redirect_to(new_session_path)
  end

  it 'handles a new email becoming unavailable before confirmation' do
    user = create_user
    sign_in(user)
    update_profile(user, email: 'contested@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    token = confirmation_token
    create_user(email: 'contested@example.test')
    patch email_change_path, params: { token: token }
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.email).not_to eq('contested@example.test')
  end

  it 'requires the current password and retains the current session while revoking others' do
    user = create_user
    sign_in(user)
    other_client = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in(user, client: other_client)
    token = reset_token(user)
    patch password_path, params: { user: { current_password: DatabaseHelpers::TEST_PASSWORD,
                                           password: 'a brand new test password',
                                           password_confirmation: 'a brand new test password' } }
    expect(response).to redirect_to(profile_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Password changed.')
    expect(response.parsed_body.css('main form')).to be_empty
    other_client.get(root_path)
    expect(other_client.response.location).to end_with(new_session_path)
    expect(User.for_password_reset(token)).to be_nil
    expect(user.reload.authenticate('a brand new test password')).to eq(user)
  end

  it 'keeps password errors on the password form without changing credentials' do
    user = create_user
    sign_in(user)
    [{ current_password: 'incorrect', password: 'a brand new test password' },
     { current_password: DatabaseHelpers::TEST_PASSWORD, password: 'short' }].each do |attributes|
      patch password_path, params: { user: attributes.merge(password_confirmation: attributes[:password]) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.css('main form').pluck('id')).to eq(%w[password-form deactivation-form])
    end
    expect(user.reload.authenticate(DatabaseHelpers::TEST_PASSWORD)).to eq(user)
  end

  it 'treats accounts from the earlier layer without an active field as active' do
    user = create_user
    User.collection.find(_id: user.id).update_one('$unset' => { active: '' })
    sign_in(user)
    get edit_profile_path
    expect(response).to have_http_status(:ok)
  end
end
