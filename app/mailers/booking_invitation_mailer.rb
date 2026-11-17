# frozen_string_literal: true

class BookingInvitationMailer < ApplicationMailer
  def invite(membership)
    @program = membership.program
    @user = membership.user
    @booking_url = calendar_program_url(@program, booking_invitation: '1')
    mail(to: @user.email, subject: @program.message('participant_access.subject', program: @program.name))
  end
end
