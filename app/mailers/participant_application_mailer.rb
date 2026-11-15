# frozen_string_literal: true

class ParticipantApplicationMailer < ApplicationMailer
  def submitted(application, recipient)
    @application = application
    @program = application.program
    @review_url = program_application_url(@program, application)
    mail(to: recipient.email, subject: "New Participation Application for #{@program.name}")
  end

  def decision(application, recipient)
    @application = application
    @program = application.program
    @application_url = program_participation_application_url(@program)
    @calendar_url = program_url(@program, section: 'calendar')
    subject = application.status == 'accepted' ? 'Application Accepted' : 'An Update About Your Application'
    mail(to: recipient.email, subject: "#{subject}: #{@program.name}")
  end
end
