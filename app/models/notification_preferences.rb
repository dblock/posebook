# frozen_string_literal: true

module NotificationPreferences
  FIELDS = %w[booking_reminders_enabled application_reminders_enabled coordinator_notifications_enabled].freeze

  def self.allowed?(user, kind)
    return true unless user
    return user.coordinator_notifications_enabled? if NotificationCatalog::COORDINATOR_ONLY.include?(kind)
    return user.application_reminders_enabled? if kind == 'application_draft'
    return user.booking_reminders_enabled? if NotificationCatalog::SCHEDULED.include?(kind)

    true
  end
end
