# frozen_string_literal: true

require 'stringio'

module PhotoFiles
  extend ActiveSupport::Concern

  included do
    field :image_id, type: BSON::ObjectId
    field :thumbnail_id, type: BSON::ObjectId
    field :created_at, type: Time, default: -> { Time.current }
  end

  class_methods do
    def storage
      Mongoid::GridFs::Photos
    end
  end

  def write_files(buffers, metadata)
    %i[image_id thumbnail_id].zip(buffers).each do |attribute, bytes|
      file = self.class.storage.put(
        StringIO.new(bytes), filename: 'photo.webp', content_type: 'image/webp',
                             metadata: metadata.merge(photo_id: id)
      )
      self[attribute] = file.id
    end
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
