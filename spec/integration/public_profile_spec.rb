# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublicProfile, :aggregate_failures, :database do
  it 'revokes consent when a stale administrator edit changes the Instagram account' do
    user = create_user(instagram_url: '@Artist.Model')
    stale_admin_edit = User.find(user.id)
    user.update!(instagram_tagging_allowed: true)
    expect(stale_admin_edit.update_by_admin(instagram_url: '@Another.Artist')).to be(true)
    expect(user.reload.instagram_url).to eq('https://www.instagram.com/another.artist/')
    expect(user.public_instagram_url).to be_nil
  end

  it 'applies a stale self-service consent grant only to the account that user selected' do
    user = create_user(instagram_url: '@Artist.Model')
    stale_profile_edit = User.find(user.id)
    user.update_by_admin(instagram_url: '@Another.Artist')
    expect(stale_profile_edit.update_profile(email: user.email, instagram_url: '@Artist.Model',
                                             instagram_tagging_allowed: '1')).to be(true)
    expect(user.reload.public_instagram_url).to eq('https://www.instagram.com/artist.model/')
  end
end
