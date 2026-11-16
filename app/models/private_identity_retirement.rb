# frozen_string_literal: true

class PrivateIdentityRetirement
  def self.call(collection = User.collection)
    collection.update_many(
      { 'public_profile_private' => true },
      { '$set' => { 'display_name' => nil, 'instagram_tagging_allowed' => false } }
    )
    collection.update_many(
      { 'public_profile_private' => true, 'profile_photos.0' => { '$exists' => true } },
      { '$set' => { 'profile_photos.$[].public' => false } }
    )
    collection.update_many({}, { '$unset' => { 'public_profile_private' => '' } })
  end
end
