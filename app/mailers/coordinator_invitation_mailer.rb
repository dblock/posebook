# frozen_string_literal: true

class CoordinatorInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @invitation_url = coordinator_invitation_url(token: token)
    mail(to: invitation.email, subject: t('coordinator_invitations.subject', name: invitation.target.name,
                                                                             role: invitation.coordinator_label))
  end
end
