# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  helper ProgramCalendarHelper
  helper BookingNotificationsHelper
  default from: -> { ENV.fetch('MAIL_FROM', 'posebook@example.com') }
  layout 'mailer'

  private

  def notification_mail(kind, scope:, recipient:, values: {}, **options)
    setting = NotificationSetting.for(scope, kind)
    content = notification_content(setting, options[:program] || scope, recipient, values)
    @notification_body = content.fetch('body')
    address = options[:to] || (recipient.respond_to?(:email) ? recipient.email : recipient)
    mail(to: address, subject: content.fetch('subject')) do |format|
      format.text { render 'configured_notifications/notify' }
      format.html { render 'configured_notifications/notify' } if options[:multipart]
    end
  end

  def notification_content(setting, context, recipient, values)
    defaults = NotificationContent.new(context, recipient).values
    setting.render(defaults.merge('reminder_days' => setting.days_after.to_s).merge(values))
  end
end
