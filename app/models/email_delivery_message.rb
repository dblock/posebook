# frozen_string_literal: true

class EmailDeliveryMessage
  def initialize(delivery)
    @delivery = delivery
  end

  def build
    send(@delivery.kind) if EmailDelivery::KINDS.include?(@delivery.kind)
  end

  private

  def booking_notification
    BookingNotification.where(id: @delivery.resource_id).first&.message
  end

  def application_draft
    ApplicationDraftMaintenance.new(@delivery.resource_id).reminder_message(expires_at: @delivery.expires_at)
  end

  def participation_admission
    event = ParticipationEvent.where(id: @delivery.resource_id).first
    ParticipationNotification.new(event).admission_message_for(@delivery.recipient_id) if event
  end

  def participation_event
    event = ParticipationEvent.where(id: @delivery.resource_id).first
    ParticipationNotification.new(event).message_for(@delivery.recipient_id) if event
  end

  def application_registration
    registration = ApplicationRegistration.available(token)
    ApplicationRegistrationMailer.verify(registration, token) if registration&.id == @delivery.resource_id
  end

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

    configured('participant_invitation', invitation.program) { ParticipantInvitationMailer.invite(invitation, token) }
  end

  def coordinator_invitation
    invitation = CoordinatorInvitation.available(token)
    return unless invitation&.id == @delivery.resource_id && invitation.email.present?

    kind = invitation.venue_id ? 'venue_coordinator_invitation' : 'program_coordinator_invitation'
    configured(kind, invitation.target) { CoordinatorInvitationMailer.invite(invitation, token) }
  end

  def booking_invitation
    membership = ProgramMembership.participants.where(id: @delivery.resource_id).first
    return unless membership && membership.booking_invited_at == @delivery.grant_invited_at

    inviter = User.active.where(id: membership.booking_invited_by_id).first
    return unless inviter && membership.program.managed_by?(inviter)

    access = BookingAccess.new(membership)
    return unless access.allowed? && !access.booking

    configured('booking_invitation', membership.program) { BookingInvitationMailer.invite(membership) }
  end

  def configured(kind, scope)
    yield if NotificationSetting.for(scope, kind).enabled
  end
end
