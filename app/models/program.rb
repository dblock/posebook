# frozen_string_literal: true

class Program
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Slug
  include HistoryTracking

  TIME_ZONES = TZInfo::Timezone.all_identifiers.freeze
  RESERVED_SLUGS = %w[new edit admin assets rails up venues sessions programs profile password registration
                      session invitation].freeze

  field :name, type: String
  field :program_label, type: String, default: 'Program'
  field :participant_label, type: String, default: 'Participant'
  field :custom_slug, type: String
  field :time_zone, type: String, default: 'UTC'
  field :pay, type: BigDecimal, default: 0
  field :instructions, type: String
  field :booking_horizon_months, type: Integer, default: 6
  field :available_weekdays, type: Array, default: ['1']
  field :no_consecutive_genders, type: Array, default: []
  field :start_time, type: String, default: '09:00'
  field :end_time, type: String
  field :schedule_revision, type: Integer, default: 0

  slug :name, :custom_slug, history: true, reserve: RESERVED_SLUGS, max_length: 100 do |program|
    (program.custom_slug.presence || program.name).to_url
  end

  track_history on: %i[name program_label participant_label custom_slug _slugs time_zone pay instructions
                       booking_horizon_months available_weekdays start_time end_time no_consecutive_genders],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true

  has_many :memberships, class_name: 'ProgramMembership', inverse_of: :program,
                         dependent: :restrict_with_error
  belongs_to :venue, inverse_of: :programs
  delegate :address, :photos, :public_instagram_handle, :public_instagram_url, to: :venue
  has_many :participant_invitations, inverse_of: :program, dependent: :restrict_with_error
  has_many :bookings, inverse_of: :program, dependent: :restrict_with_error
  has_many :schedule_exceptions, class_name: 'ProgramScheduleException', inverse_of: :program,
                                 dependent: :restrict_with_error

  before_validation do
    self.name = name.to_s.strip
    self.program_label = program_label.to_s.squish
    self.participant_label = participant_label.to_s.squish
    self.custom_slug = custom_slug.to_s.strip.presence
    self.available_weekdays = Array(available_weekdays).map(&:to_s).compact_blank.uniq
    self.no_consecutive_genders = Array(no_consecutive_genders).map(&:to_s).compact_blank.uniq
    self.end_time = end_time.to_s.strip.presence
  end
  validates :name, presence: true, length: { maximum: 100 }
  validates :program_label, :participant_label, presence: true, length: { maximum: 40 },
                                                format: { with: /\A[a-zA-Z][a-zA-Z0-9 -]*\z/ }
  validates :custom_slug, length: { maximum: 100 }
  validates :time_zone, inclusion: { in: TIME_ZONES }
  validates :pay, numericality: { greater_than_or_equal_to: 0 }
  validates :instructions, length: { maximum: 5000 }
  validates :booking_horizon_months, numericality: { only_integer: true, greater_than: 0 }
  validates :start_time, format: { with: ProgramSchedule::TIME_FORMAT }
  validates :end_time, format: { with: ProgramSchedule::TIME_FORMAT }, allow_nil: true
  validate do
    errors.add(:end_time, 'must differ from the start time') if end_time.present? && end_time == start_time
  end
  validate do
    errors.add(:available_weekdays, :invalid) if available_weekdays.empty? ||
                                                 (available_weekdays - %w[0 1 2 3 4 5 6]).any?
  end
  validate do
    errors.add(:custom_slug, 'must include a letter or number') if (custom_slug.presence || name).to_url.blank?
  end
  validate do
    errors.add(:no_consecutive_genders, :invalid) if (no_consecutive_genders - User::GENDERS).any?
  end
  def self.visible_to(user)
    return all if user.system_admin?

    ids = ProgramMembership.where(user_id: user.id,
                                  :roles.in => %w[program_coordinator
                                                  participant]).distinct(:program_id)
    where('$or' => [{ :id.in => ids }, { :venue_id.in => Venue.coordinated_by(user).distinct(:id) }])
  end

  def self.managed_by(user)
    return all if user.system_admin?

    ids = ProgramMembership.coordinators.where(user_id: user.id).distinct(:program_id)
    where('$or' => [{ :id.in => ids }, { :venue_id.in => Venue.coordinated_by(user).distinct(:id) }])
  end

  def managed_by?(user)
    venue.coordinated_by?(user) || memberships.coordinators.exists?(user_id: user.id)
  end

  def participant?(user)
    memberships.participants.exists?(user_id: user.id)
  end

  def terminology
    { program_label: program_label.downcase, participant_label: participant_label.downcase,
      program_title: program_label.titleize, participant_title: participant_label.titleize,
      participants_label: participant_label.pluralize.downcase, participant_article: participant_article }
  end

  def participant_article
    participant_label.match?(/\A[aeiou]/i) ? 'an' : 'a'
  end

  def message(key, **)
    I18n.t(key, **terminology, **)
  end
end
