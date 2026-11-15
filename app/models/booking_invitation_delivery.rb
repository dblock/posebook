# frozen_string_literal: true

class BookingInvitationDelivery
  def initialize(program:, user:)
    @mutation = ParticipantAccessMutation.new(program: program, user: user)
  end

  def call(id)
    membership = @mutation.invite(id)
    return :skipped unless membership
    return :failed unless Rails.configuration.x.password_reset_delivery_enabled

    EmailDelivery.enqueue('booking_invitation', membership, grant_invited_at: membership.booking_invited_at)
    :queued
  rescue EmailDelivery::Unavailable => e
    NewRelic::Agent.notice_error(e)
    :failed
  end
end
