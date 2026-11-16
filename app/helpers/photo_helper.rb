# frozen_string_literal: true

module PhotoHelper
  def owner_photo_path(owner, photo, **)
    owner.is_a?(Venue) ? venue_photo_path(owner, photo, **) : program_photo_path(owner, photo, **)
  end

  def public_photo_series(owner, primary)
    owner.photos.where(PrimaryPhoto::PUBLIC_SELECTOR).where(:id.ne => primary.id).order_by(created_at: :asc)
  end
end
