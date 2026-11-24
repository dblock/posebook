# frozen_string_literal: true

class BookingNotificationSetting < NotificationSetting
  KINDS = NotificationCatalog::BOOKING_KINDS
  SCHEDULED = NotificationCatalog::SCHEDULED
  COORDINATOR_ONLY = (%w[attendance_confirmed coordinator_alert] + NotificationCatalog::COORDINATOR_COPIES.values).freeze
end
