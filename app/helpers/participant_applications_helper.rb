# frozen_string_literal: true

module ParticipantApplicationsHelper
  def participation_actor_label(event, source)
    return 'System' unless event.actor_id
    return source&.name.presence || 'Applicant' if event.actor_id == event.user_id

    event.actor.name
  end

  def participation_event_label(event)
    return 'Application: Not Now' if event.action == 'application_declined'

    event.action.humanize.titleize
  end
end
