# frozen_string_literal: true

class EmailChangeMailer < ApplicationMailer
  def confirm(user, token)
    notification_mail('email_change', scope: nil, recipient: user, to: user.pending_email,
                                      values: { 'confirmation_url' => email_change_url(token: token),
                                                'recipient_email' => user.pending_email })
  end
end
