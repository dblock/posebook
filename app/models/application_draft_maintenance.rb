# frozen_string_literal: true

class ApplicationDraftMaintenance
  EXPIRES_AFTER = 30.days

  def self.run
    ParticipantApplication.where(status: 'draft', profile_shared_at: nil)
                          .any_of({ draft_started_at: nil, :created_at.lte => EXPIRES_AFTER.ago },
                                  { :draft_started_at.lte => EXPIRES_AFTER.ago },
                                  { draft_reminded_at: nil })
                          .only(:id).each { |record| new(record.id).process }
  end

  def initialize(id)
    @id = id
  end

  def process
    ParticipantApplication.with_session do |session|
      session.with_transaction do
        record = draft
        next unless record

        if record.draft_created_at <= EXPIRES_AFTER.ago
          record.discard_draft!(expired: true)
        elsif record.draft_reminded_at.nil? && remindable?(record)
          enqueue_reminder(record, session)
        end
      end
    end
  end

  def reminder_message(expires_at: nil)
    record = draft
    return unless record && remindable?(record)
    return if expires_at && expires_at != record.draft_created_at + EXPIRES_AFTER

    ParticipantApplicationMailer.draft_reminder(record, @user)
  end

  private

  def draft
    ParticipantApplication.where(id: @id, status: 'draft', profile_shared_at: nil).first
  end

  def remindable?(record)
    @user = User.active.where(id: record.user_id).first
    unless @user&.email_verified_at && @user.application_reminders_enabled? && accepting?(record.program_id)
      return false
    end

    reminder_due?(record)
  end

  def reminder_due?(record)
    setting = NotificationSetting.for(@program, 'application_draft')
    setting.enabled && record.draft_created_at <= setting.days_after.days.ago &&
      record.draft_created_at > EXPIRES_AFTER.ago
  end

  def accepting?(program_id)
    @program = Program.where(id: program_id).first
    @program&.booking_active? && @program.applications_enabled? && !@program.participant?(@user)
  end

  def enqueue_reminder(record, session)
    record.update!(draft_reminded_at: Time.current)
    expires_at = record.draft_created_at + EXPIRES_AFTER
    EmailDelivery.enqueue_in_transaction('application_draft', record, session: session, expires_at: expires_at)
  end
end
