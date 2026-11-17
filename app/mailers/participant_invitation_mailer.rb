# frozen_string_literal: true

class ParticipantInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    values = { 'invitation_url' => invitation_url(token: token),
               'recipient_name' => invitation.name.presence || 'Participant',
               'participant_name' => invitation.name.presence || 'Participant',
               'participant_label' => invitation.program.participant_label.downcase }
    notification_mail('participant_invitation', scope: invitation.program, recipient: invitation.email, values: values)
  end
end
