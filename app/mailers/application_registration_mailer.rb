# frozen_string_literal: true

class ApplicationRegistrationMailer < ApplicationMailer
  def verify(registration, token)
    values = { 'verification_url' => application_verification_url(token: token) }
    notification_mail('application_registration', scope: nil, program: registration.program,
                                                  recipient: registration.email, values: values)
  end
end
