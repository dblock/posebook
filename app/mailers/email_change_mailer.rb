# frozen_string_literal: true

class EmailChangeMailer < ApplicationMailer
  def confirm(user, token)
    @confirmation_url = email_change_url(token: token)
    mail(to: user.pending_email, subject: t('email_changes.subject'))
  end
end
