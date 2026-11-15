# frozen_string_literal: true

class ParticipationNotification
  DECISIONS = { 'application_accepted' => 'accepted', 'application_declined' => 'declined' }.freeze

  def initialize(event)
    @event = event
  end

  def enqueue(session:)
    ids = recipient_ids
    return unless ids

    unless ids.any? && Rails.configuration.x.password_reset_delivery_enabled
      raise EmailDelivery::Unavailable, 'Application notifications are unavailable'
    end

    ids.each do |id|
      EmailDelivery.enqueue_in_transaction('participation_event', @event, session: session, recipient_id: id)
    end
  end

  def message_for(recipient_id)
    application = ParticipantApplication.where(id: @event.source_id, program_id: @event.program_id,
                                               user_id: @event.user_id).first
    recipient = User.active.where(id: recipient_id).first
    return unless application&.profile_shared_at && recipient

    if @event.action == 'application_submitted'
      submission_message(application, recipient)
    elsif DECISIONS[@event.action]
      decision_message(application, recipient)
    end
  end

  private

  def recipient_ids
    return coordinator_ids if @event.action == 'application_submitted'

    [@event.user_id] if DECISIONS[@event.action]
  end

  def coordinator_ids
    ids = ProgramMembership.coordinators.where(program_id: @event.program_id).pluck(:user_id)
    ids += VenueMembership.coordinators.where(venue_id: @event.program.venue_id).pluck(:user_id)
    User.active.where(:id.in => ids.uniq).pluck(:id)
  end

  def submission_message(application, recipient)
    return unless application.status == 'pending' && coordinator_ids.include?(recipient.id)

    ParticipantApplicationMailer.submitted(application, recipient)
  end

  def decision_message(application, recipient)
    return unless application.status == DECISIONS[@event.action] && recipient.id == application.user_id &&
                  recipient.email_verified_at
    return if application.status == 'accepted' && !application.program.participant?(recipient)

    ParticipantApplicationMailer.decision(application, recipient)
  end
end
