# frozen_string_literal: true

class ModelInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @venue = invitation.venue
    @invitation_url = invitation_url(token: token)
    mail(to: invitation.email, subject: t('invitations.subject', venue: @venue.name))
  end
end
