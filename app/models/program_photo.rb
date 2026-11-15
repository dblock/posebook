# frozen_string_literal: true

class ProgramPhoto
  include Mongoid::Document
  include PhotoFiles

  belongs_to :program, inverse_of: :photos
  index({ program_id: 1, created_at: 1 })
  after_destroy :delete_files

  def self.add(program, upload)
    buffers = ProfileImage.new(upload).buffers
    photo = new(program: program)
    photo.write_files(buffers, program_id: program.id)
    photo.save!
    photo
  rescue StandardError
    photo&.delete_files
    raise
  end
end
