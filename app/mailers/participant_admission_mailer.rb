# frozen_string_literal: true

class ParticipantAdmissionMailer < ApplicationMailer
  def accepted(event, participant, recipient)
    @program = event.program
    @participant = participant
    @source = event.action == 'invitation_accepted' ? 'A personal invitation' : 'A participation application'
    @history_url = history_program_applications_url(@program)
    mail(to: recipient.email, subject: "Participation Accepted: #{@program.name}")
  end
end
