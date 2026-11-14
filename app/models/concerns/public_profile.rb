# frozen_string_literal: true

module PublicProfile
  extend ActiveSupport::Concern

  FIELDS = %i[display_name instagram_url instagram_tagging_allowed].freeze

  included do
    field :display_name, type: String
    field :instagram_url, type: String
    field :instagram_tagging_allowed, type: Mongoid::Boolean, default: false
    before_validation :normalize_public_profile
    before_save :synchronize_instagram_consent
    validates :display_name, length: { maximum: 100 }, allow_nil: true
    validates :instagram_url, presence: true, if: :instagram_tagging_allowed?
    validate :validate_instagram_profile
  end

  def public_name
    display_name.presence || name
  end

  def public_instagram_url
    InstagramProfile.normalize(instagram_url) if instagram_tagging_allowed?
  end

  def public_instagram_username
    public_instagram_url&.split('/')&.last
  end

  private

  def prepare_admin_public_profile
    normalize_public_profile
    self.instagram_tagging_allowed = false if instagram_url_changed?
  end

  def normalize_public_profile
    self.display_name = display_name.to_s.strip.presence
    self.instagram_url = InstagramProfile.normalize(instagram_url) || instagram_url.to_s.strip.presence
  end

  def synchronize_instagram_consent
    return unless instagram_url_changed? || instagram_tagging_allowed_changed?

    # Mongoid otherwise omits unchanged values, which could transfer consent in a race.
    %w[instagram_url instagram_tagging_allowed].each do |field|
      delayed_atomic_sets[field] = self[field] unless attribute_changed?(field)
    end
  end

  def validate_instagram_profile
    return if instagram_url.blank? || InstagramProfile.normalize(instagram_url)

    errors.add(:instagram_url, 'must link to an Instagram profile, not a post or another website')
  end
end
