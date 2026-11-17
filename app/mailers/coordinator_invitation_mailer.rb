# frozen_string_literal: true

class CoordinatorInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    kind = invitation.venue_id ? 'venue_coordinator_invitation' : 'program_coordinator_invitation'
    notification_mail(kind, scope: invitation.target, recipient: invitation.email,
                            values: { 'invitation_url' => coordinator_invitation_url(token: token),
                                      'recipient_name' => invitation.name.presence || 'Coordinator',
                                      'coordinator_label' => invitation.coordinator_label })
  end
end
