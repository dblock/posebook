# frozen_string_literal: true

namespace :users do
  desc 'Convert legacy Instagram profile URLs to handles without changing preferences or history'
  task migrate_instagram_handles: :environment do
    User.collection.find(instagram_url: { '$exists' => true }).each do |attributes|
      value = attributes.fetch('instagram_handle') { attributes['instagram_url'] }
      handle = InstagramProfile.normalize(value)
      abort "Invalid Instagram handle for user #{attributes['_id']}" if value.present? && handle.nil?

      selector = attributes.slice('_id', 'instagram_url')
      selector['instagram_handle'] = attributes.fetch('instagram_handle', { '$exists' => false })
      User.collection.find(selector).update_one(
        '$set' => { instagram_handle: handle }, '$unset' => { instagram_url: '' }
      )
    end
  end
end
