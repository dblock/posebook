# frozen_string_literal: true

module PhotoHelper
  def owner_photo_path(owner, photo, **)
    owner.is_a?(Venue) ? venue_photo_path(owner, photo, **) : program_photo_path(owner, photo, **)
  end

  def public_photo_series(owner, primary)
    owner.public_photo_ids.reject { |id| id == primary.id }
  end
end
