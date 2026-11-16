# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublicProfile, :aggregate_failures, :database do
  it 'masks inactive identity at the public helpers and restores saved preferences only on reactivation' do
    user = create_user(display_name: 'Saved Public Name', instagram_handle: '@Public.Participant',
                       instagram_tagging_allowed: true)
    user.deactivate
    expect(user.reload).to have_attributes(public_name: 'To be announced', public_instagram_handle: nil,
                                           public_instagram_url: nil, display_name: 'Saved Public Name',
                                           instagram_handle: 'public.participant', instagram_tagging_allowed: true)
    user.reactivate
    expect(user.reload).to have_attributes(public_name: 'Saved Public Name',
                                           public_instagram_handle: 'public.participant',
                                           public_instagram_url: 'https://www.instagram.com/public.participant/')
  end

  it 'keeps a stale administrator edit tied to its selected handle and tagging preference' do
    user = create_user(instagram_handle: '@Public.Participant')
    stale_admin_edit = User.find(user.id)
    user.update!(instagram_tagging_allowed: true)
    expect(stale_admin_edit.update_by_admin(instagram_handle: '@Another.Participant')).to be(true)
    expect(user.reload.instagram_handle).to eq('another.participant')
    expect(user.public_instagram_url).to be_nil
  end

  it 'applies stale self-service tagging preferences only to the selected handle' do
    user = create_user(instagram_handle: '@Public.Participant')
    stale_profile_edit = User.find(user.id)
    user.update_by_admin(instagram_handle: '@Another.Participant')
    expect(stale_profile_edit.update_profile(email: user.email, instagram_handle: '@Public.Participant',
                                             instagram_tagging_allowed: '1')).to be(true)
    expect(user.reload.public_instagram_url).to eq('https://www.instagram.com/public.participant/')
  end
end
