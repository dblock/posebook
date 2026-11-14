# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public identity privacy', :aggregate_failures, :database, type: :request do
  let(:user) do
    create_user(display_name: 'Saved Public Name', instagram_handle: '@Artist.Model', instagram_tagging_allowed: true)
  end

  def update_privacy(value)
    patch profile_path, params: { user: { email: user.email, public_profile_private: value } }
  end

  it 'audits the owner choosing privacy without erasing saved sharing preferences' do
    sign_in(user)
    update_privacy('1')
    expect(response).to redirect_to(profile_path)
    expect(user.reload).to have_attributes(public_name: 'To be announced', public_instagram_url: nil,
                                           public_instagram_handle: nil, display_name: 'Saved Public Name',
                                           instagram_tagging_allowed: true)
    expect(user.history_tracks.last.modified).to include('public_profile_private' => true)
    expect(user.history_tracks.last.modifier_id).to eq(user.id)
    follow_redirect!
    expect(response.parsed_body.text).to include('Profile saved.', 'Private: To be announced on public calendars',
                                                 'Hidden while your information is private')
  end

  it 'renders private sharing controls disabled while keeping the privacy choice available' do
    user.update!(public_profile_private: true)
    sign_in(user)
    get edit_profile_path
    group = response.parsed_body.at_css('[data-public-profile-fields]')
    expect(group.key?('disabled')).to be(true)
    expect(group.css('input').pluck('name')).to include('user[display_name]', 'user[instagram_handle]',
                                                        'user[instagram_tagging_allowed]')
    toggle = response.parsed_body.at_css('[data-profile-privacy-toggle]')
    expect(toggle.key?('checked')).to be(true)
    expect(toggle.ancestors('fieldset[disabled]')).to be_empty
  end

  it 'restores saved public preferences only when the owner turns privacy off' do
    user.update!(public_profile_private: true)
    sign_in(user)
    update_privacy('0')
    expect(response).to redirect_to(profile_path)
    expect(user.reload.public_name).to eq('Saved Public Name')
    expect(user.public_instagram_url).to eq('https://www.instagram.com/artist.model/')
    get edit_profile_path
    expect(response.parsed_body.at_css('[data-public-profile-fields]').key?('disabled')).to be(false)
  end

  it 'accepts privacy during first-account registration' do
    attributes = user_attributes(public_profile_private: '1')
    post registration_path, params: { user: attributes }
    registered = track_record(User.find_by(email: attributes[:email]))
    expect(response).to redirect_to(root_path)
    expect(registered.public_name).to eq('To be announced')
    get edit_profile_path
    expect(response.parsed_body.at_css('[data-public-profile-fields]').key?('disabled')).to be(true)
  end

  it 'accepts privacy during invited registration even alongside public sharing fields' do
    invitation = create_model_invitation(create_venue, create_user(roles: ['system_admin']))
    attributes = user_attributes(public_profile_private: '1', display_name: 'Hidden Public Name',
                                 instagram_handle: '@Artist.Model', instagram_tagging_allowed: '1')
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    registered = track_record(User.find_by(email: attributes[:email]))
    track_model_membership(invitation.venue, registered)
    expect(response).to redirect_to(venue_path(invitation.venue))
    expect(registered).to have_attributes(public_name: 'To be announced', public_instagram_url: nil,
                                          display_name: 'Hidden Public Name', instagram_tagging_allowed: true)
  end

  it 'lets an administrator change privacy preferences while auditing the change' do
    user.update!(public_profile_private: true)
    sign_in(create_user(roles: ['system_admin']))
    get edit_admin_user_path(user)
    expect(response.parsed_body.css('input[name="user[public_profile_private]"]')).not_to be_empty
    expect(response.parsed_body.at_css('[data-public-profile-fields]').key?('disabled')).to be(true)
    patch admin_user_path(user), params: { user: { name: 'Updated Account Name', email: user.email,
                                                   public_profile_private: '0' } }
    expect(response).to redirect_to(admin_users_path)
    expect(user.reload).to have_attributes(name: 'Updated Account Name', public_profile_private: false,
                                           public_name: 'Saved Public Name',
                                           public_instagram_handle: 'artist.model')
    expect(user.history_tracks.last.modified).to include('public_profile_private' => false)
  end
end
