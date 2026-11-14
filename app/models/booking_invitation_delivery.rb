# frozen_string_literal: true

require 'net/smtp'

class BookingInvitationDelivery
  def initialize(venue:, user:)
    @mutation = ModelAccessMutation.new(venue: venue, user: user)
  end

  def call(id)
    membership = @mutation.invite(id)
    return :skipped unless membership
    return :failed unless Rails.configuration.x.password_reset_delivery_enabled

    BookingInvitationMailer.invite(membership).deliver_now
    :sent
  rescue IOError, SystemCallError, Timeout::Error, Net::SMTPError
    :failed
  end
end
