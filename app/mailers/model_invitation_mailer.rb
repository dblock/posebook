# frozen_string_literal: true

class ModelInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @drawing_session = invitation.drawing_session
    @invitation_url = invitation_url(token: token)
    mail(to: invitation.email, subject: t('invitations.subject', drawing_session: @drawing_session.name))
  end
end
