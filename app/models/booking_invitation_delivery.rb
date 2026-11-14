# frozen_string_literal: true

require 'net/smtp'

class BookingInvitationDelivery
  def initialize(program:, user:)
    @mutation = ParticipantAccessMutation.new(program: program, user: user)
  end

  def call(id)
    membership = @mutation.invite(id)
    return :skipped unless membership
    return :failed unless Rails.configuration.x.password_reset_delivery_enabled

    BookingInvitationMailer.invite(membership).deliver_now
    :sent
  rescue IOError, SystemCallError, Timeout::Error, Net::SMTPError => e
    NewRelic::Agent.notice_error(e)
    :failed
  end
end
