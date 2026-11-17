# frozen_string_literal: true

class ParticipationNotification
  DECISIONS = { 'application_accepted' => 'accepted', 'application_declined' => 'declined' }.freeze
  ADMISSIONS = %w[application_accepted invitation_accepted].freeze

  def initialize(event)
    @event = event
  end

  def enqueue(session:)
    ids = recipient_ids
    queue('participation_event', ids, session) if ids
    enqueue_admission(session)
  end

  def message_for(recipient_id)
    application = ParticipantApplication.where(id: @event.source_id, program_id: @event.program_id,
                                               user_id: @event.user_id).first
    recipient = User.active.where(id: recipient_id).first
    return unless application&.profile_shared_at && recipient && latest_event?(application)

    if @event.action == 'application_submitted'
      submission_message(application, recipient)
    elsif DECISIONS[@event.action]
      decision_message(application, recipient)
    end
  end

  def admission_message_for(recipient_id)
    return unless valid_admission_source?

    recipient = User.active.where(id: recipient_id).first
    participant = current_participant
    return unless recipient && participant && coordinator_ids.include?(recipient.id)

    ParticipantAdmissionMailer.accepted(@event, participant, recipient)
  end

  private

  def latest_event?(application)
    application.events.order_by(created_at: :desc, id: :desc).first&.id == @event.id
  end

  def current_participant
    program = @event.program
    participant = User.active.where(id: @event.user_id).first
    participant if participant && program&.booking_active? && program.participant?(participant)
  end

  def queue(kind, ids, session)
    unless ids.any? && Rails.configuration.x.password_reset_delivery_enabled
      raise EmailDelivery::Unavailable, 'Participation notifications are unavailable'
    end

    ids.each do |id|
      EmailDelivery.enqueue_in_transaction(kind, @event, session: session, recipient_id: id)
    end
  end

  def enqueue_admission(session)
    return unless ADMISSIONS.include?(@event.action) && Rails.configuration.x.password_reset_delivery_enabled

    ids = coordinator_ids
    queue('participation_admission', ids, session) if ids.any?
  end

  def valid_admission_source?
    if @event.action == 'invitation_accepted'
      ParticipantInvitation.exists?(id: @event.source_id, program_id: @event.program_id,
                                    used_by_id: @event.user_id, :used_at.ne => nil)
    elsif @event.action == 'application_accepted'
      ParticipantApplication.exists?(id: @event.source_id, program_id: @event.program_id,
                                     user_id: @event.user_id, status: 'accepted', :profile_shared_at.ne => nil)
    end
  end

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
