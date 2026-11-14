# frozen_string_literal: true

class ParticipantInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @program = invitation.program
    @invitation_url = invitation_url(token: token)
    mail(to: invitation.email, subject: @program.message('invitations.subject', program: @program.name))
  end
end
