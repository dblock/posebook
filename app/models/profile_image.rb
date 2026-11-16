# frozen_string_literal: true

require 'marcel'
require 'vips'

class ProfileImage
  class Invalid < StandardError; end

  MAX_BYTES = 10.megabytes
  MAX_PIXELS = 40_000_000
  LOADERS = %w[jpegload pngload webpload].freeze
  CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

  def initialize(upload)
    validate_upload(upload)
    @source = Vips::Image.new_from_file(upload.tempfile.path, access: :sequential, fail_on: :warning)
    validate_source
  rescue Vips::Error
    raise Invalid, 'This photo could not be read. Choose a valid JPEG, PNG, or WebP image.'
  end

  def buffers
    image = @source.autorot.thumbnail_image(1600, height: 1600, size: :down).colourspace(:srgb).copy_memory
    [encode(image), encode(image.thumbnail_image(400, height: 400, crop: :centre, size: :both))]
  rescue Vips::Error
    raise Invalid, 'This photo could not be processed. Choose another image.'
  end

  private

  def validate_upload(upload)
    unless upload.respond_to?(:tempfile) && upload.tempfile.size.between?(1, MAX_BYTES)
      raise Invalid, 'Choose a JPEG, PNG, or WebP photo no larger than 10 MB.'
    end

    return if CONTENT_TYPES.include?(Marcel::MimeType.for(upload.tempfile))

    raise Invalid, 'Choose a JPEG, PNG, or WebP photo.'
  end

  def validate_source
    return if LOADERS.include?(@source.get('vips-loader')) && @source.width * @source.height <= MAX_PIXELS

    raise Invalid, 'Choose a JPEG, PNG, or WebP photo no larger than 10 MB.'
  end

  def encode(image)
    image.write_to_buffer('.webp', Q: 82, strip: true, effort: 4)
  end
end
