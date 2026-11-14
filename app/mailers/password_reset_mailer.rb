# frozen_string_literal: true

class PasswordResetMailer < ApplicationMailer
  def reset(user, token)
    @reset_url = edit_password_reset_url(token: token)
    mail(to: user.email, subject: t('password_resets.subject'))
  end
end
