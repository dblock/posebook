# frozen_string_literal: true

class PhotoGallery
  attr_reader :user

  def initialize(user, viewer)
    @user = user
    @viewer = viewer
  end

  def editable?
    @viewer && (@viewer.id == user.id || @viewer.system_admin?)
  end

  def private_access?
    editable? || organizer?
  end

  def photos
    private_access? ? user.profile_photos.to_a : user.public_photos
  end

  def accessible?
    private_access? || photos.any?
  end

  private

  def organizer?
    return false unless @viewer
    return @organizer unless @organizer.nil?

    drawing_session_ids = DrawingSessionMembership.models.where(user_id: user.id).pluck(:drawing_session_id)
    @organizer = DrawingSession.managed_by(@viewer).exists?(:id.in => drawing_session_ids)
  end
end
