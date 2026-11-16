# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Administrator user editing', :aggregate_failures, :database, type: :request do
  def update_user(user, **attributes)
    patch admin_user_path(user), params: { user: { name: user.name, email: user.email, phone: user.phone }
                                                .merge(attributes) }
  end

  def expect_own_page_redirects(admin)
    { admin_user_path(admin) => profile_path, edit_admin_user_path(admin) => edit_profile_path,
      photos_admin_user_path(admin) => photos_profile_path, security_admin_user_path(admin) => security_profile_path,
      history_admin_user_path(admin) => history_profile_path }.each do |path, own_path|
      get path
      expect(response).to redirect_to(own_path)
    end
  end

  def profile_tabs
    nav = response.parsed_body.at_css('.profile-tabs')
    [nav.css('.page-tab-group').map { |group| group.css('a, .page-tab-disabled').map(&:text) },
     nav.css('.page-tab-disabled').map(&:text), nav.at_css('[aria-current="page"]').text]
  end

  def expect_user_cannot_access_admin(user, admin)
    sign_in(user)
    get profile_path
    expect(response.parsed_body.at_css("header a[href='#{admin_users_path}']")).to be_nil
    expect_user_admin_routes_forbidden(admin)
  end

  def expect_user_admin_routes_forbidden(admin)
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
    get bookings_admin_user_path(admin)
    expect(response).to have_http_status(:forbidden)
  end

  it 'shows Users only in the administrator header and redirects admins to their own profile pages' do
    admin = create_user(roles: ['system_admin'])
    user = create_user
    sign_in(admin)
    get profile_path
    expect(response.parsed_body.at_css("header a[href='#{admin_users_path}']").text).to eq('Users')
    expect(response.parsed_body.css('.profile-tabs a').map(&:text)).not_to include('Users')
    get participant_path(user)
    expect(response).to redirect_to(admin_user_path(user))
    get admin_user_path(user)
    expect(response.parsed_body.css('.breadcrumbs a').map(&:text)).to eq(['Users'])
    expect(response.parsed_body.at_css('.breadcrumbs [aria-current="page"]').text).to eq(user.name)
    expect_own_page_redirects(admin)
    get edit_profile_path
    expect(response.parsed_body.css('.breadcrumbs a').map(&:text)).to eq(['Users', "#{admin.name} (You)"])
    expect_user_cannot_access_admin(user, admin)
  end

  def grant_profile_access(*accounts)
    accounts.each do |account|
      program = create_program
      grant_participant_access(program, account)
      grant_coordinator_access(create_program, account)
    end
  end

  def expect_matching_tabs(page, user)
    own_path = page == 'profile' ? profile_path : public_send("#{page}_profile_path")
    admin_path = page == 'profile' ? admin_user_path(user) : public_send("#{page}_admin_user_path", user)
    own = tabs_for(own_path)
    expect(tabs_for(admin_path)).to eq(own)
    expect_admin_tab_links(user)
  end

  def expect_admin_tab_links(user)
    expect(response.parsed_body.css('.profile-tabs a').pluck('href'))
      .to all(start_with(admin_user_path(user)))
  end

  def tabs_for(path)
    get path
    expect(response).to have_http_status(:ok)
    profile_tabs
  end

  it 'matches the profile tabs for admin user pages' do
    admin = create_user(roles: ['system_admin'])
    user = create_user
    grant_profile_access(admin, user)
    sign_in(admin)
    pages = %w[profile bookings programs applications history edit photos security]
    pages.each do |page|
      expect_matching_tabs(page, user)
    end
    expect(profile_tabs.first).to eq([%w[Profile Bookings Programs Applications History], %w[Edit Photos Security]])
  end

  it 'shows another user bookings without booking controls' do
    user = create_user
    program = create_program
    grant_participant_access(program, user)
    track_booking(BookingMutation.new(program: program, user: user)
                   .book(date: Date.current.next_occurring(:monday).iso8601))
    sign_in(create_user(roles: ['system_admin']))
    get bookings_admin_user_path(user)
    expect(response.parsed_body.at_css('.upcoming-booking h2').text).to eq('Upcoming Booking')
    expect(response.body).not_to include('Cancel Booking', 'Reschedule', 'Choose a Date', "I'll be there!")
  end

  it 'lets admins send another user a password reset email from Security' do
    user = create_user
    sign_in(create_user(roles: ['system_admin']))
    get security_admin_user_path(user)
    expect(response.parsed_body.css('main button').map(&:text)).to eq(['Send Password Reset Email', 'Deactivate'])
    expect(response.body).not_to include('Change Password', 'Deactivate My Account')
    ActionMailer::Base.deliveries.clear
    post password_reset_admin_user_path(user)
    expect(response).to redirect_to(security_admin_user_path(user))
    expect(flash[:notice]).to eq("Password reset email queued for #{user.email}.")
    deliver_emails
    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
    sign_in(create_user)
    post password_reset_admin_user_path(user)
    expect(response).to have_http_status(:forbidden)
  end

  it 'lets admins deactivate and reactivate another user from Security' do
    user = create_user
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    patch admin_user_path(user), params: { active: false, return_to: 'security' }
    expect(response).to redirect_to(security_admin_user_path(user))
    expect(user.reload).not_to be_active
    get security_admin_user_path(user)
    expect(response.parsed_body.css('main button').map(&:text)).to eq(['Reactivate'])
    patch admin_user_path(user), params: { active: true, return_to: 'security' }
    expect(user.reload).to be_active
    get security_admin_user_path(create_user(roles: ['system_admin']))
    expect(response.body).to include('Administrator accounts cannot be deactivated.')
  end

  it 'shows all account information only to admins' do
    user = create_user(name: 'Shown User', phone: '2125551234', gender: 'female', instagram_handle: 'shown.user',
                       pending_email: 'next@example.test', active: false)
    sign_in(create_user(roles: ['system_admin']))
    get admin_user_path(user)
    details = response.parsed_body.at_css('.account-details').text
    expect(details).to include('Inactive', 'Shown User', user.email, 'Female', '@shown.user')
    expect(response.body).to include('next@example.test')
    sign_in(create_user)
    get admin_user_path(user)
    expect(response).to have_http_status(:forbidden)
  end

  it 'labels account access states consistently without changing their controls' do
    create_user
    create_user(active: false)
    sign_in(create_user(roles: ['system_admin']))
    get admin_users_path
    expect(response.parsed_body.css('.breadcrumbs [aria-hidden="true"]').map(&:text)).to eq(['>'])
    expect(response.parsed_body.css('td:nth-child(5) .status-label').map(&:text))
      .to contain_exactly('Active', 'Active', 'Inactive')
    expect(response.parsed_body.at_css('td:nth-child(5) .status-label-danger').text).to eq('Inactive')
    expect(response.parsed_body.at_css('td:nth-child(6) .status-label-neutral').text).to eq('Protected')
    expect(response.body).to include('Reactivate', 'Deactivate')
    expect(response.parsed_body.css('.user-accounts button.secondary-action').map(&:text))
      .to contain_exactly('Reactivate', 'Deactivate')
  end

  def expect_admin_row_links(row, admin)
    expect(row.css("a[href='#{admin_user_path(admin)}']").map(&:text)).to include("#{admin.name} (You)", admin.email)
  end

  def expect_admin_edit_link(row, admin)
    expect(row.css('a').find { |link| link.text == 'Edit' }['href']).to eq(edit_admin_user_path(admin))
  end

  def expect_admin_user_row(admin)
    own_row = response.parsed_body.at_css("#user_#{admin.id}")
    expect_admin_row_links(own_row, admin)
    expect(own_row.text).to include("#{admin.name} (You)", admin.email)
    expect_admin_edit_link(own_row, admin)
  end

  it 'shows linked placeholder portraits only for users without a profile photo' do
    user = create_user(name: 'Participant With Photo')
    photo = user.profile_photos.create!(public: true)
    without_photo = create_user(name: 'Participant Without Photo')
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    get admin_users_path
    expect_admin_user_row(admin)
    portrait = response.parsed_body.at_css(".participant-portrait[href='#{admin_user_path(user)}'] img")
    placeholder = response.parsed_body.at_css(".participant-portrait[href='#{admin_user_path(without_photo)}'] img")
    expect(portrait['src']).to eq(participant_photo_path(user, photo, thumbnail: 1))
    expect(portrait['alt']).to eq("Profile photo of #{user.name}")
    expect(placeholder['src']).to include('profile-placeholder')
    expect(placeholder['alt']).to eq("No profile photo for #{without_photo.name}")
    expect([portrait, placeholder].map { |image| image.attributes.values_at('width', 'height').map(&:value) })
      .to eq([%w[64 64], %w[64 64]])
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
    update_user(user, name: 'Edited Participant', email: " #{user.email.upcase} ", phone: '1 (212) 555-1234',
                      roles: ['system_admin'], active: false, password: 'a forbidden password change')
    expect(response).to redirect_to(edit_admin_user_path(user))
    follow_redirect!
    expect(response.body).to include('User information saved.', 'Edited Participant', '+1 (212) 555-1234')
    expect(user.reload).to have_attributes(name: 'Edited Participant', phone: '+12125551234', roles: [],
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
    expect(response).to redirect_to(edit_admin_user_path(user))
    expect(user.reload).to have_attributes(email: 'new-address@example.test', email_verified_at: nil,
                                           pending_email: nil, email_change_digest: nil, email_change_expires_at: nil)
    expect(User.for_password_reset(token)).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
    client.get(root_path)
    expect(client.response.location).to end_with(new_session_path)
    client.post(session_path, params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD })
    expect(client.response.location).to end_with(root_path)
  end

  it 'allows administrators to edit public profile and tagging preferences' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    get edit_admin_user_path(user)
    expect(response.parsed_body.css('input[name="user[instagram_tagging_allowed]"]')).not_to be_empty
    update_user(user, display_name: 'Alex Participant', instagram_handle: '@Alex.Participant',
                      instagram_tagging_allowed: '1')
    expect(response).to redirect_to(edit_admin_user_path(user))
    expect(user.reload.public_name).to eq('Alex Participant')
    expect(user.instagram_handle).to eq('alex.participant')
    expect(user.public_instagram_url).to eq('https://www.instagram.com/alex.participant/')
    expect(user.history_tracks.last.modified).to include('instagram_tagging_allowed' => true)
  end

  it 'preserves tagging when an administrator changes handles and supports turning it off explicitly' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user(instagram_handle: '@Public.Participant', instagram_tagging_allowed: true)
    update_user(user, name: 'Updated Participant', instagram_handle: 'instagram.com/PUBLIC.PARTICIPANT')
    expect(user.reload.public_instagram_handle).to eq('public.participant')
    update_user(user, instagram_handle: '@Another.Participant')
    expect(user.reload.instagram_handle).to eq('another.participant')
    expect(user.public_instagram_handle).to eq('another.participant')
    update_user(user, instagram_tagging_allowed: '0')
    expect(user.reload.public_instagram_url).to be_nil
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

  it 'requires phone and gender on administrator edits' do
    sign_in(create_user(roles: ['system_admin']))
    user = create_user
    get edit_admin_user_path(user)
    expect(response.parsed_body.at_css('input[name="user[phone]"][required]')).to be_present
    expect(response.parsed_body.at_css('select[name="user[gender]"][required]')).to be_present
    update_user(user, phone: '', gender: '')
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload).to have_attributes(phone: '+12025550101', gender: 'other')
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
    update_user(user, name: 'Updated Inactive Participant')
    expect(response).to redirect_to(edit_admin_user_path(user))
    expect(user.reload).to have_attributes(name: 'Updated Inactive Participant', active: false,
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
