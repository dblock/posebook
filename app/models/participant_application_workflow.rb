# frozen_string_literal: true

class ParticipantApplicationWorkflow
  include ProgramScheduleLock

  class Invalid < StandardError; end
  class Conflict < StandardError; end

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def submit(message:, consent:, version: nil)
    ParticipantApplication.with_session do |session|
      session.with_transaction { submit_application(message, consent, version, session) }
    end
    @application
  end

  def review(id, status:, version:, notes: nil)
    raise Invalid, 'Choose Accept or Not Now.' unless %w[accepted declined].include?(status)

    with_schedule_lock do |session|
      actor = User.active.find(@user.id)
      Program.managed_by(actor).find(@program.id)
      @application = ParticipantApplication.where(program_id: @program.id).find(id)
      check_decision(status, version)
      admit_participant(session) if status == 'accepted'
      transition(status, actor, notes, session)
    end
    @application
  end

  def withdraw(id, version:)
    ParticipantApplication.with_session do |session|
      session.with_transaction do
        actor = User.active.find(@user.id)
        @application = ParticipantApplication.where(program_id: @program.id, user_id: actor.id).find(id)
        check_decision('withdrawn', version)
        transition('withdrawn', actor, nil, session)
      end
    end
    @application
  end

  private

  def submit_application(message, consent, version, session)
    actor = User.active.find(@user.id)
    @program = Program.find(@program.id)
    unless @program.applications_enabled? && @program.booking_active? && actor.email_verified_at &&
           consent == '1' && !@program.participant?(actor)
      raise Invalid, 'Applications require an open program, verified account, and profile-sharing consent.'
    end

    @application = ApplicationDraft.new(program: @program, user: actor)
                                   .submit(message: message, version: version, session: session)
    record_event('submitted', actor, nil, session)
  end

  def check_decision(status, version)
    unless version.to_s.match?(/\A[0-9]+\z/) && version.to_i == @application.lock_version &&
           %w[pending declined].include?(@application.status)
      raise Conflict, 'This application changed. Reload it before making a decision.'
    end
    return if %w[accepted declined withdrawn].include?(status) && status != @application.status

    raise Invalid, 'Choose Accept or Not Now.'
  end

  def admit_participant(session)
    raise Invalid, 'An inactive program or account cannot be accepted.' unless @program.booking_active?

    participant = User.active.find(@application.user_id)
    ProgramMembership.grant_participant_access(@program, participant, session: session)
  end

  def transition(status, actor, notes, session)
    @application.update!(status: status, lock_version: @application.lock_version + 1)
    record_event(status, actor, notes, session)
  end

  def record_event(action, actor, notes, session)
    event = @application.record_event!(action, actor: actor, notes: notes)
    ParticipationNotification.new(event).enqueue(session: session)
  end
end
