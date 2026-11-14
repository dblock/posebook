# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublicProfile, :aggregate_failures, :database do
  it 'keeps a stale administrator edit tied to its selected handle and tagging preference' do
    user = create_user(instagram_handle: '@Artist.Model')
    stale_admin_edit = User.find(user.id)
    user.update!(instagram_tagging_allowed: true)
    expect(stale_admin_edit.update_by_admin(instagram_handle: '@Another.Artist')).to be(true)
    expect(user.reload.instagram_handle).to eq('another.artist')
    expect(user.public_instagram_url).to be_nil
  end

  it 'applies stale self-service tagging preferences only to the selected handle' do
    user = create_user(instagram_handle: '@Artist.Model')
    stale_profile_edit = User.find(user.id)
    user.update_by_admin(instagram_handle: '@Another.Artist')
    expect(stale_profile_edit.update_profile(email: user.email, instagram_handle: '@Artist.Model',
                                             instagram_tagging_allowed: '1')).to be(true)
    expect(user.reload.public_instagram_url).to eq('https://www.instagram.com/artist.model/')
  end

  it 'preserves a concurrent privacy choice when a stale administrator edits the profile' do
    user = create_user(instagram_handle: '@Artist.Model', instagram_tagging_allowed: true)
    stale_admin_edit = User.find(user.id)
    user.update!(public_profile_private: true)
    expect(stale_admin_edit.update_by_admin(name: 'Updated Name', instagram_handle: '@Another.Artist')).to be(true)
    expect(user.reload).to have_attributes(public_profile_private: true, public_name: 'To be announced',
                                           public_instagram_url: nil)
  end
end
