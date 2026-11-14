# frozen_string_literal: true

require 'net/smtp'

class BookingInvitationDelivery
  def initialize(drawing_session:, user:)
    @mutation = ModelAccessMutation.new(drawing_session: drawing_session, user: user)
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
