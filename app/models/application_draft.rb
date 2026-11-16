# frozen_string_literal: true

class ApplicationDraft
  PROFILE_FIELDS = %w[name phone gender display_name instagram_handle instagram_tagging_allowed].freeze

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def save(version:, message: nil, profile: {}, photos: [], remove_photo_id: nil)
    ParticipantApplication.with_session do |session|
      session.with_transaction { save_record(message, profile, version) }
    end
    update_photos(photos, remove_photo_id)
    @record
  end

  def submit(message:, version:, session:)
    raise ArgumentError, 'Submission requires a transaction' unless session.in_transaction?

    record = records.first
    if record&.draft?
      submit_draft(record, message, version)
    else
      raise ParticipantApplicationWorkflow::Conflict, 'This application changed. Reload it.' if version.present?

      ParticipantApplication.create!(program: @program, user: @user, **submission_attributes(message))
    end
  end

  def discard(version:)
    ParticipantApplication.with_session do |session|
      session.with_transaction do
        record = records.first!
        check_version!(record, version)
        record.destroy!
      end
    end
  end

  private

  def save_record(message, profile, version)
    require_applicant!
    @record = records.first || ParticipantApplication.new(program: @program, user: @user, status: 'draft')
    check_version!(@record, version)
    @record.assign_attributes(message: message,
                              draft_profile: @record.draft_profile.merge(profile.to_h.stringify_keys
                                                                              .slice(*PROFILE_FIELDS)))
    @record.lock_version += 1 unless @record.new_record?
    @record.save!
  end

  def require_applicant!
    @user = User.active.find(@user.id)
    @program = Program.find(@program.id)
    return if @user.email_verified_at && @program.applications_enabled? && @program.booking_active? &&
              !@program.participant?(@user)

    raise ParticipantApplicationWorkflow::Invalid, 'This program is not accepting an application from this account.'
  end

  def submit_draft(record, message, version)
    check_version!(record, version)
    @user.assign_attributes(record.draft_profile.slice(*PROFILE_FIELDS))
    @user.save!
    record.update!(**submission_attributes(message), lock_version: record.lock_version + 1, draft_profile: {})
    record
  end

  def update_photos(photos, remove_photo_id)
    if remove_photo_id.present?
      @user.profile_photos.find(remove_photo_id).remove(@user)
    else
      photos.compact_blank.each { |upload| ProfilePhoto.add(@user, upload) }
    end
  end

  def records
    ParticipantApplication.where(program_id: @program.id, user_id: @user.id)
  end

  def check_version!(record, version)
    return if record.new_record? && version.blank?
    return if record.persisted? && record.draft? && version.to_s == record.draft_revision

    raise ParticipantApplicationWorkflow::Conflict, 'This application changed. Reload it before saving.'
  end

  def submission_attributes(message)
    { status: 'pending', name: @user.name, email: @user.email, gender: @user.gender,
      message: message, profile_shared_at: Time.current, submitted_at: Time.current }
  end
end
