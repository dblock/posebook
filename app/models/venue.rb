# frozen_string_literal: true

class Venue
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Slug
  include HistoryTracking

  field :name, type: String
  field :custom_slug, type: String
  field :address, type: String
  field :instagram_handle, type: String
  field :program_schema_version, type: Integer, default: 1

  slug :name, :custom_slug, history: true, reserve: Program::RESERVED_SLUGS, max_length: 100 do |venue|
    (venue.custom_slug.presence || venue.name).to_url
  end
  track_history on: %i[name custom_slug _slugs address instagram_handle],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true

  has_many :memberships, class_name: 'VenueMembership', inverse_of: :venue, dependent: :restrict_with_error
  has_many :programs, inverse_of: :venue, dependent: :restrict_with_error
  has_many :photos, class_name: 'VenuePhoto', inverse_of: :venue, dependent: :destroy

  before_validation do
    self.name = name.to_s.strip
    self.custom_slug = custom_slug.to_s.strip.presence
    self.address = address.to_s.strip
    self.instagram_handle = InstagramProfile.normalize(instagram_handle) || instagram_handle.to_s.strip.presence
  end
  validates :name, presence: true, length: { maximum: 100 }
  validates :custom_slug, length: { maximum: 100 }
  validates :address, presence: true, length: { maximum: 500 }
  validate do
    errors.add(:custom_slug, 'must include a letter or number') if (custom_slug.presence || name).to_url.blank?
    if instagram_handle.present? && !InstagramProfile.normalize(instagram_handle)
      errors.add(:instagram_handle, 'must be an Instagram handle or profile URL, not a post or another website')
    end
  end

  def public_instagram_handle
    InstagramProfile.normalize(instagram_handle)
  end

  def public_instagram_url
    InstagramProfile.url(instagram_handle)
  end

  def self.coordinated_by(user)
    return all if user.system_admin?

    where(:id.in => VenueMembership.coordinators.where(user_id: user.id).distinct(:venue_id))
  end

  def self.visible_to(user)
    return all if user.system_admin?

    ids = coordinated_by(user).pluck(:id) + Program.visible_to(user).distinct(:venue_id)
    where(:id.in => ids)
  end

  def coordinated_by?(user)
    user && (user.system_admin? || memberships.coordinators.exists?(user_id: user.id))
  end
end
