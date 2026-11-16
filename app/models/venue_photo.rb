# frozen_string_literal: true

class VenuePhoto
  include Mongoid::Document
  include PhotoFiles

  belongs_to :venue, inverse_of: :photos
  field :public, type: Mongoid::Boolean, default: true
  index({ venue_id: 1, created_at: 1 })
  after_destroy :delete_files

  scope :visible, -> { where(:public.ne => false) }

  def self.add(venue, upload)
    buffers = ProfileImage.new(upload).buffers
    photo = new(venue: venue)
    photo.write_files(buffers, venue_id: venue.id)
    photo.save!
    photo
  rescue StandardError
    photo&.delete_files
    raise
  end

  def change_visibility(value)
    update!(public: value)
    venue.update!(primary_photo_id: nil) if !value && venue.primary_photo_id == id
  end

  def select_primary
    update!(public: true)
    venue.update!(primary_photo_id: id)
  end
end
