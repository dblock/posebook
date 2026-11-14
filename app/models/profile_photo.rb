# frozen_string_literal: true

require 'stringio'

class ProfilePhoto
  include Mongoid::Document

  LIMIT = 10

  embedded_in :user
  field :public, type: Mongoid::Boolean, default: false
  field :image_id, type: BSON::ObjectId
  field :thumbnail_id, type: BSON::ObjectId
  field :created_at, type: Time, default: -> { Time.current }

  def self.storage
    Mongoid::GridFs::Photos
  end

  def self.add(user, upload)
    raise ProfileImage::Invalid, 'You can have up to 10 photos. Delete one before uploading another.' if
      user.profile_photos.length >= LIMIT

    buffers = ProfileImage.new(upload).buffers
    photo = new
    photo.write_files(buffers, user)
    photo.attach(user)
    photo
  rescue StandardError
    photo&.delete_files
    raise
  end

  def write_files(buffers, owner)
    %i[image_id thumbnail_id].zip(buffers).each do |attribute, bytes|
      file = self.class.storage.put(
        StringIO.new(bytes), filename: 'photo.webp', content_type: 'image/webp',
                             metadata: { user_id: owner.id, photo_id: id }
      )
      self[attribute] = file.id
    end
  end

  def attach(owner)
    # A conditional single-document write enforces the limit across simultaneous uploads.
    result = User.collection.find(_id: owner.id, 'profile_photos.9' => { '$exists' => false })
                 .update_one('$push' => { profile_photos: attributes })
    return if result.matched_count == 1

    raise ProfileImage::Invalid, 'You can have up to 10 photos. Delete one before uploading another.'
  end

  def change_visibility(owner, value)
    User.collection.find(_id: owner.id, 'profile_photos._id' => id)
        .update_one('$set' => { 'profile_photos.$.public' => value })
  end

  def remove(owner)
    User.collection.find(_id: owner.id).update_one('$pull' => { profile_photos: { _id: id } })
    delete_files
  end

  def bytes(thumbnail: false)
    self.class.storage.get(thumbnail ? thumbnail_id : image_id).data
  end

  def delete_files
    [image_id, thumbnail_id].each { |file_id| delete_file(file_id) }
  end

  private

  def delete_file(file_id)
    self.class.storage.get(file_id).destroy if file_id
  rescue Mongoid::Errors::DocumentNotFound
    nil
  end
end
