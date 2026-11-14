# frozen_string_literal: true

class Venue
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Slug
  include HistoryTracking

  TIME_ZONES = TZInfo::Timezone.all_identifiers.freeze
  RESERVED_SLUGS = %w[new edit admin assets rails up venues profile password registration session invitation].freeze

  field :name, type: String
  field :custom_slug, type: String
  field :address, type: String
  field :time_zone, type: String, default: 'America/New_York'
  field :model_pay, type: BigDecimal, default: 140
  field :instructions, type: String
  field :booking_horizon_months, type: Integer, default: 6
  field :available_weekdays, type: Array, default: ['1']
  field :start_time, type: String, default: '18:30'
  field :schedule_revision, type: Integer, default: 0

  slug :name, :custom_slug, history: true, reserve: RESERVED_SLUGS, max_length: 100 do |venue|
    (venue.custom_slug.presence || venue.name).to_url
  end

  track_history on: %i[name custom_slug _slugs address time_zone model_pay instructions booking_horizon_months
                       available_weekdays start_time],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true

  has_many :memberships, class_name: 'VenueMembership', inverse_of: :venue, dependent: :restrict_with_error
  has_many :model_invitations, inverse_of: :venue, dependent: :restrict_with_error
  has_many :model_bookings, inverse_of: :venue, dependent: :restrict_with_error
  has_many :schedule_exceptions, class_name: 'VenueScheduleException', inverse_of: :venue,
                                 dependent: :restrict_with_error

  before_validation do
    self.name = name.to_s.strip
    self.custom_slug = custom_slug.to_s.strip.presence
    self.address = address.to_s.strip
    self.available_weekdays = Array(available_weekdays).map(&:to_s).compact_blank.uniq
  end
  validates :name, presence: true, length: { maximum: 100 }
  validates :custom_slug, length: { maximum: 100 }
  validates :address, presence: true, length: { maximum: 500 }
  validates :time_zone, inclusion: { in: TIME_ZONES }
  validates :model_pay, numericality: { greater_than_or_equal_to: 0 }
  validates :instructions, length: { maximum: 5000 }
  validates :booking_horizon_months, numericality: { only_integer: true, greater_than: 0 }
  validates :start_time, format: { with: VenueSchedule::TIME_FORMAT }
  validate do
    errors.add(:available_weekdays, :invalid) if available_weekdays.empty? ||
                                                 (available_weekdays - %w[0 1 2 3 4 5 6]).any?
  end
  validate do
    errors.add(:custom_slug, 'must include a letter or number') if (custom_slug.presence || name).to_url.blank?
  end

  def self.visible_to(user)
    return all if user.system_admin?

    ids = VenueMembership.where(user_id: user.id, :roles.in => %w[manage_schedule model]).distinct(:venue_id)
    where(:id.in => ids)
  end

  def self.managed_by(user)
    return all if user.system_admin?

    ids = VenueMembership.schedule_managers.where(user_id: user.id).distinct(:venue_id)
    where(:id.in => ids)
  end

  def managed_by?(user)
    user.system_admin? || memberships.schedule_managers.exists?(user_id: user.id)
  end

  def model?(user)
    memberships.models.exists?(user_id: user.id)
  end
end
