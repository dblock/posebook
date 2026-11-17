# frozen_string_literal: true

class BookingInvitationMailer < ApplicationMailer
  def invite(membership)
    values = { 'booking_url' => calendar_program_url(membership.program, booking_invitation: '1') }
    notification_mail('booking_invitation', scope: membership.program, recipient: membership.user,
                                            multipart: true, values: values)
  end
end
