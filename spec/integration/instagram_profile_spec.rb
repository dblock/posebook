# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe InstagramProfile, :aggregate_failures, :database do
  def migrate_handles
    Rails.application.load_tasks unless Rake::Task.task_defined?('users:migrate_instagram_handles')
    Rake::Task['users:migrate_instagram_handles'].reenable
    Rake::Task['users:migrate_instagram_handles'].invoke
  end

  it 'converts old URLs once while preserving preferences and retained audit history' do
    user = create_user(public_profile_private: true)
    user.collection.find(_id: user.id).update_one(
      '$set' => { instagram_url: 'https://www.instagram.com/Artist.Model/?igsh=tracking',
                  instagram_tagging_allowed: true },
      '$unset' => { instagram_handle: '' }
    )
    history_count = user.history_tracks.count
    2.times { migrate_handles }
    expect(user.reload).to have_attributes(instagram_handle: 'artist.model', instagram_tagging_allowed: true,
                                           public_profile_private: true, public_instagram_url: nil)
    expect(user.attributes).not_to have_key('instagram_url')
    expect(user.history_tracks.count).to eq(history_count)
  end

  it 'does not replace a new or explicitly cleared handle with a legacy URL' do
    [nil, 'current.artist'].each do |handle|
      user = create_user
      user.collection.find(_id: user.id).update_one(
        '$set' => { instagram_handle: handle, instagram_url: 'https://www.instagram.com/old.artist/' }
      )
      migrate_handles
      expect(user.reload.instagram_handle).to eq(handle)
      expect(user.attributes).not_to have_key('instagram_url')
    end
  end
end
