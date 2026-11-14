# frozen_string_literal: true

class Venue
  include Mongoid::Document
  include Mongoid::Timestamps

  TIME_ZONES = TZInfo::Timezone.all_identifiers.freeze

  field :name, type: String
  field :address, type: String
  field :time_zone, type: String, default: 'America/New_York'
  field :model_pay, type: BigDecimal, default: 140
  field :instructions, type: String
  field :booking_horizon_months, type: Integer, default: 6
  field :available_weekdays, type: Array, default: ['1']

  has_many :memberships, class_name: 'VenueMembership', inverse_of: :venue, dependent: :restrict_with_error
  has_many :model_invitations, inverse_of: :venue, dependent: :restrict_with_error
  has_many :model_bookings, inverse_of: :venue, dependent: :restrict_with_error

  before_validation do
    self.name = name.to_s.strip
    self.address = address.to_s.strip
    self.available_weekdays = Array(available_weekdays).map(&:to_s).compact_blank.uniq
  end
  validates :name, presence: true, length: { maximum: 100 }
  validates :address, presence: true, length: { maximum: 500 }
  validates :time_zone, inclusion: { in: TIME_ZONES }
  validates :model_pay, numericality: { greater_than_or_equal_to: 0 }
  validates :instructions, length: { maximum: 5000 }
  validates :booking_horizon_months, numericality: { only_integer: true, greater_than: 0 }
  validate do
    errors.add(:available_weekdays, :invalid) if available_weekdays.empty? ||
                                                 (available_weekdays - %w[0 1 2 3 4 5 6]).any?
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
