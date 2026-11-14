# frozen_string_literal: true

class BookingInvitationMailer < ApplicationMailer
  def invite(membership)
    @drawing_session = membership.drawing_session
    @user = membership.user
    @booking_url = drawing_session_url(@drawing_session, booking_invitation: '1')
    mail(to: @user.email, subject: t('model_access.subject', drawing_session: @drawing_session.name))
  end
end
