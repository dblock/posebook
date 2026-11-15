# frozen_string_literal: true

class EmailDeliveryMessage
  def initialize(delivery)
    @delivery = delivery
  end

  def build
    case @delivery.kind
    when 'password_reset' then password_reset
    when 'email_change' then email_change
    when 'participant_invitation' then participant_invitation
    when 'coordinator_invitation' then coordinator_invitation
    when 'booking_invitation' then booking_invitation
    end
  end

  private

  def token
    @token ||= @delivery.token
  end

  def password_reset
    user = User.for_password_reset(token)
    PasswordResetMailer.reset(user, token) if user&.id == @delivery.resource_id
  end

  def email_change
    user = User.active.where(id: @delivery.resource_id, email_change_digest: Digest::SHA256.hexdigest(token),
                             :email_change_expires_at.gt => Time.current).first
    EmailChangeMailer.confirm(user, token) if user&.pending_email.present?
  end

  def participant_invitation
    invitation = ParticipantInvitation.available(token)
    return unless invitation&.id == @delivery.resource_id && invitation.email.present?

    inviter = User.active.where(id: invitation.invited_by_id).first
    return unless inviter && invitation.program&.managed_by?(inviter)

    ParticipantInvitationMailer.invite(invitation, token)
  end

  def coordinator_invitation
    invitation = CoordinatorInvitation.available(token)
    CoordinatorInvitationMailer.invite(invitation, token) if invitation&.id == @delivery.resource_id &&
                                                             invitation.email.present?
  end

  def booking_invitation
    membership = ProgramMembership.participants.where(id: @delivery.resource_id).first
    return unless membership && membership.booking_invited_at == @delivery.grant_invited_at

    inviter = User.active.where(id: membership.booking_invited_by_id).first
    return unless inviter && membership.program.managed_by?(inviter)

    access = BookingAccess.new(membership)
    BookingInvitationMailer.invite(membership) if access.allowed? && !access.booking
  end
end
