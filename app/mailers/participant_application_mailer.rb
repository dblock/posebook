# frozen_string_literal: true

class ParticipantApplicationMailer < ApplicationMailer
  def draft_reminder(application, recipient)
    values = { 'application_url' => program_participation_application_url(application.program) }
    notification_mail('application_draft', scope: application.program, recipient: recipient, values: values)
  end

  def submitted(application, recipient)
    values = { 'participant_name' => application.name.presence || 'Applicant',
               'review_url' => program_application_url(application.program, application) }
    notification_mail('application_submitted', scope: application.program, recipient: recipient, values: values)
  end

  def decision(application, recipient)
    values = { 'application_url' => program_participation_application_url(application.program),
               'calendar_url' => calendar_program_url(application.program) }
    notification_mail("application_#{application.status}", scope: application.program, recipient: recipient,
                                                           values: values)
  end
end
