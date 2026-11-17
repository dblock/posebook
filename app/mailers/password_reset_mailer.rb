# frozen_string_literal: true

class PasswordResetMailer < ApplicationMailer
  def reset(user, token)
    notification_mail('password_reset', scope: nil, recipient: user,
                                        values: { 'reset_url' => edit_password_reset_url(token: token) })
  end
end
