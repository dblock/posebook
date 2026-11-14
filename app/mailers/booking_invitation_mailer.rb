# frozen_string_literal: true

class BookingInvitationMailer < ApplicationMailer
  def invite(membership)
    @venue = membership.venue
    @user = membership.user
    @booking_url = venue_url(@venue, booking_invitation: '1')
    mail(to: @user.email, subject: t('model_access.subject', venue: @venue.name))
  end
end
