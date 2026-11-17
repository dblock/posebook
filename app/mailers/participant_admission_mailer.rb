# frozen_string_literal: true

class ParticipantAdmissionMailer < ApplicationMailer
  def accepted(event, participant, recipient)
    source = event.action == 'invitation_accepted' ? 'A personal invitation' : 'A participation application'
    values = { 'participant_name' => participant.name.presence || event.program.participant_label,
               'admission_source' => source, 'history_url' => history_program_applications_url(event.program) }
    notification_mail('participation_admission', scope: event.program, recipient: recipient, values: values)
  end
end
