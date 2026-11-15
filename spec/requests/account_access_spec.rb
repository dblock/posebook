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
    expect(response.parsed_body.css('main form').pluck('id')).to eq(%w[password-form deactivation-form])
    details = response.parsed_body.at_css('#deactivate-account')
    expect(details.text).to include('It does not delete your account.', 'will no longer be shared publicly',
                                    'Existing bookings are not canceled.', 'authorized administrators and organizers')
    expect(details.at_css('a')['href']).to eq(privacy_path(anchor: 'retention-and-your-choices'))
    expect(user.reload).to be_active
  end

  it 'retains bookings and memberships with attributed history on self-deactivation' do
    user = create_user
    program = create_program
    membership = grant_participant_access(program, user)
    date = Date.current.next_occurring(:monday).iso8601
    booking = track_booking(BookingMutation.new(program: program, user: user).book(date: date))
    sign_in(user)
    post account_deactivation_path, params: { current_password: DatabaseHelpers::TEST_PASSWORD }
    follow_redirect!
    expect(response.body).to include('Your profile is no longer shared publicly',
                                     'your account and booking history have been retained')
    expect(membership.reload.roles).to include('participant')
    expect(booking.reload).to have_attributes(user_id: user.id, status: 'confirmed', date: Date.iso8601(date))
    expect(user.history_tracks.where('modified.active' => false).last.modifier_id).to eq(user.id)
  end

  it 'revokes every browser and remembered login on self-deactivation, including after reactivation' do
    user = create_user
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.post(session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD, remember_me: '1' })
    sign_in(user)
    post account_deactivation_path, params: { current_password: DatabaseHelpers::TEST_PASSWORD }
    [self, client].each do |browser|
      browser.get(profile_path)
      expect(browser.response.location).to end_with(new_session_path)
    end
    user.reactivate
    client.get(profile_path)
    expect(client.response.location).to end_with(new_session_path)
  end

  it 'protects system admin accounts from deactivation' do
    user = create_user(roles: ['system_admin'])
    sign_in(user)
    get security_profile_path
    expect(response.body).to include('System admin accounts stay active')
    expect(response.parsed_body.at_css('#deactivation-form')).to be_nil
    expect(response.parsed_body.at_css('#password-form')).to be_present
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
    get edit_admin_user_path(user)
    expect(response).to have_http_status(:forbidden)
    patch admin_user_path(user), params: { user: { name: 'Forbidden' } }
    expect(response).to have_http_status(:forbidden)
    expect(user.reload.name).not_to eq('Forbidden')
    patch admin_user_path(user), params: { active: false }
    expect(response).to have_http_status(:forbidden)
    expect(user.reload).to be_active
  end

  it 'lets a system admin deactivate and reactivate accounts while preserving their roles' do
    admin = create_user(roles: ['system_admin'])
    user = create_user
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.post(session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD, remember_me: '1' })
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

  it 'changes account access even when legacy profile fields fail current validation' do
    admin = create_user(roles: ['system_admin'])
    user = create_user
    user.set(phone: nil, gender: nil, instagram_tagging_allowed: true)
    sign_in(admin)
    patch admin_user_path(user), params: { active: false }
    expect(response).to redirect_to(admin_users_path)
    follow_redirect!
    expect(response.body).to include('Account access updated.')
    expect(user.reload).not_to be_active
    expect(user.history_tracks.last).to have_attributes(modified: { 'active' => false }, modifier_id: admin.id)
    patch admin_user_path(user), params: { active: true }
    follow_redirect!
    expect(response.body).to include('Account access updated.')
    expect(user.reload).to have_attributes(active: true, phone: nil, gender: nil, instagram_tagging_allowed: true)
    expect(user.history_tracks.last).to have_attributes(modified: { 'active' => true }, modifier_id: admin.id)
  end

  it 'shows a clear error if the target becomes a protected administrator before the update' do
    admin = create_user(roles: ['system_admin'])
    user = create_user
    User.find(user.id).set(roles: ['system_admin'])
    allow(User).to receive(:find).with(user.id.to_s).and_return(user)
    sign_in(admin)
    patch admin_user_path(user), params: { active: false }
    follow_redirect!
    expect(response.parsed_body.at_css('[role="alert"]').text)
      .to eq('Account access could not be updated. Refresh the page and try again.')
    expect(user.reload).to be_active
  end
end
