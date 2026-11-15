# frozen_string_literal: true

module PrimaryPhoto
  extend ActiveSupport::Concern

  included do
    field :primary_photo_id, type: BSON::ObjectId
  end

  def primary_photo(photos = self.photos.order_by(created_at: :asc).to_a)
    photos.find { |photo| photo.id == primary_photo_id } || photos.first
  end
end
