# frozen_string_literal: true

class ProfilePhoto
  include Mongoid::Document
  include PhotoFiles

  embedded_in :user
  field :public, type: Mongoid::Boolean, default: false

  def self.add(user, upload)
    buffers = ProfileImage.new(upload).buffers
    photo = new
    photo.write_files(buffers, user_id: user.id)
    photo.attach(user)
    photo
  rescue StandardError
    photo&.delete_files
    raise
  end

  def attach(owner)
    result = User.collection.find(_id: owner.id).update_one('$push' => { profile_photos: attributes })
    return if result.matched_count == 1

    raise ProfileImage::Invalid, 'This account is no longer available.'
  end

  def change_visibility(owner, value)
    User.collection.find(_id: owner.id, 'profile_photos._id' => id)
        .update_one('$set' => { 'profile_photos.$.public' => value })
  end

  def remove(owner)
    User.collection.find(_id: owner.id).update_one('$pull' => { profile_photos: { _id: id } })
    User.collection.find(_id: owner.id, primary_profile_photo_id: id)
        .update_one('$unset' => { primary_profile_photo_id: true })
    delete_files
  end

  def select_primary(owner)
    User.collection.find(_id: owner.id, 'profile_photos._id' => id)
        .update_one('$set' => { primary_profile_photo_id: id })
  end
end
