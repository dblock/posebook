# frozen_string_literal: true

class BookingNotificationMailer < ApplicationMailer
  helper BookingNotificationsHelper

  def notify(notification)
    @notification = notification
    @recipient = notification.recipient
    content = rendered_content
    @body = content.fetch('body')
    @reminder = notification.scheduled? && @recipient.id == notification.booking.user_id
    @unsubscribe_url = booking_reminder_preference_url(token: @recipient.booking_reminder_token) if @reminder
    mail(to: @recipient.email, subject: content.fetch('subject').squish)
  end

  private

  def rendered_content
    setting = BookingNotificationSetting.for(@notification.booking.program, @notification.kind)
    content = BookingNotificationContent.new(@notification.booking, previous: @notification.previous_booking,
                                                                    previous_location: @notification.previous_location)
    setting.render(content.values)
  end
end
