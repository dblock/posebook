# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  helper VenueCalendarHelper
  default from: -> { ENV.fetch('MAIL_FROM', 'posebook@example.com') }
  layout 'mailer'
end
