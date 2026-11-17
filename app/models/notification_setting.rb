# frozen_string_literal: true

class NotificationSetting
  include ActiveModel::Model
  include ActiveModel::Attributes
  include NotificationTemplates

  FIELDS = %w[enabled timing days_before days_after time subject body].freeze
  attr_accessor :parent_attributes, :local_attributes

  attribute :kind, :string
  attribute :enabled, :boolean, default: true
  attribute :timing, :string, default: 'days_before'
  attribute :days_before, :integer, default: 5
  attribute :days_after, :integer, default: 7
  attribute :time, :string, default: '12:00'
  attribute :subject, :string
  attribute :body, :string

  validates :kind, inclusion: { in: NotificationCatalog::KINDS }
  validates :timing, inclusion: { in: %w[previous_session_end days_before] }
  validates :days_before, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }
  validates :days_after, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 30 }
  validates :time, format: { with: ProgramSchedule::TIME_FORMAT }
  validate :validate_timing
  validate { errors.add(:enabled, 'cannot be disabled for security email') if mandatory? && !enabled }

  def self.all_for(scope)
    defaults = NotificationDefaults.current.notification_settings
    NotificationCatalog.kinds_for(scope).map { |kind| self.for(scope, kind, defaults: defaults) }
  end

  def self.for(scope, kind, defaults: NotificationDefaults.current.notification_settings)
    parent = parent_for(scope, kind, defaults)
    local = scope&.notification_settings&.fetch(kind, {}) || {}
    new(merge_overrides(parent, local).merge('kind' => kind)).tap do |setting|
      setting.parent_attributes = parent
      setting.local_attributes = local
    end
  end

  def self.parent_for(scope, kind, defaults)
    parent = NotificationCatalog.defaults(kind)
    parent = merge_overrides(parent, defaults.fetch(kind, {})) unless scope.is_a?(NotificationDefaults)
    return parent unless scope.is_a?(Program)

    merge_overrides(parent, scope.venue.notification_settings.fetch(kind, {}))
  end

  def self.merge_overrides(parent, overrides)
    parent.merge(overrides.reject { |_, value| value.nil? || (value.is_a?(String) && value.blank?) })
  end

  def mandatory? = NotificationCatalog::SYSTEM_KINDS.include?(kind)

  def stored_attributes
    attributes.slice(*FIELDS).each_with_object({}) do |(field, value), result|
      value = normalize_value(value)
      baseline = %w[subject body].include?(field) ? inherited_template(field) : parent_attributes[field]
      result[field] = value unless value.nil? || value == normalize_value(baseline)
    end
  end

  private

  def normalize_value(value)
    value.is_a?(String) ? value.gsub("\r\n", "\n").strip.presence : value
  end

  def validate_timing
    return if NotificationCatalog::SCHEDULED.include?(kind) || timing == 'days_before'

    errors.add(:timing, 'must use days before the session')
  end
end
