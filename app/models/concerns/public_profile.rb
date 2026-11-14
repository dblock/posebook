# frozen_string_literal: true

module PublicProfile
  extend ActiveSupport::Concern

  FIELDS = %i[display_name instagram_handle instagram_tagging_allowed public_profile_private].freeze

  included do
    embeds_many :profile_photos
    before_destroy :delete_profile_photo_files
    field :display_name, type: String
    field :instagram_handle, type: String
    field :instagram_tagging_allowed, type: Mongoid::Boolean, default: false
    field :public_profile_private, type: Mongoid::Boolean, default: false
    before_validation :normalize_public_profile
    before_save :synchronize_instagram_preferences
    validates :display_name, length: { maximum: 100 }, allow_nil: true
    validates :instagram_handle, presence: true, if: :instagram_tagging_allowed?
    validate :validate_instagram_profile
  end

  def public_name
    return 'To be announced' if public_profile_private?

    display_name.presence || name
  end

  def public_instagram_url
    InstagramProfile.url(public_instagram_handle)
  end

  def public_instagram_handle
    InstagramProfile.normalize(instagram_handle) if instagram_tagging_allowed? && !public_profile_private?
  end

  def public_photos
    return [] unless active? && !public_profile_private?

    profile_photos.select(&:public?)
  end

  private

  def delete_profile_photo_files
    self.class.where(id: id).first&.profile_photos&.each(&:delete_files)
  end

  def normalize_public_profile
    self.display_name = display_name.to_s.strip.presence
    self.instagram_handle = InstagramProfile.normalize(instagram_handle) || instagram_handle.to_s.strip.presence
  end

  def synchronize_instagram_preferences
    return unless instagram_handle_changed? || instagram_tagging_allowed_changed?

    # Keep the selected account and tagging preference together across concurrent edits.
    %w[instagram_handle instagram_tagging_allowed].each do |field|
      delayed_atomic_sets[field] = self[field] unless attribute_changed?(field)
    end
  end

  def validate_instagram_profile
    return if instagram_handle.blank? || InstagramProfile.normalize(instagram_handle)

    errors.add(:instagram_handle, 'must be an Instagram handle or profile URL, not a post or another website')
  end
end
