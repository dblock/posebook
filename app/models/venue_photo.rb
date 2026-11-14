# frozen_string_literal: true

class VenuePhoto
  include Mongoid::Document
  include PhotoFiles

  belongs_to :venue, inverse_of: :photos
  index({ venue_id: 1, created_at: 1 })
  after_destroy :delete_files

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
end
