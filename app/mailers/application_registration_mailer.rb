# frozen_string_literal: true

class ApplicationRegistrationMailer < ApplicationMailer
  def verify(registration, token)
    @program = registration.program
    @verification_url = application_verification_url(token: token)
    mail(to: registration.email, subject: "Verify Your Email to Apply to #{@program.name}")
  end
end
