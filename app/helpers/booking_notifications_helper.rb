# frozen_string_literal: true

module BookingNotificationsHelper
  def booking_notification_body(text)
    parts = text.split(%r{(https?://[^\s<>]+)}).map do |part|
      part.match?(%r{\Ahttps?://}) ? link_to(part, part) : part
    end
    simple_format(safe_join(parts))
  end
end
