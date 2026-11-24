# frozen_string_literal: true

module NotificationCatalog
  COORDINATOR_COPIES = {
    'booking_created' => 'coordinator_booking_created', 'booking_changed' => 'coordinator_booking_changed',
    'booking_canceled' => 'coordinator_booking_canceled', 'attendance_cleared' => 'coordinator_attendance_cleared'
  }.freeze
  BOOKING_KINDS = (%w[booking_created booking_changed booking_canceled attendance_confirmed attendance_cleared
                      confirmation_request confirmation_reminder session_reminder coordinator_alert] +
                   COORDINATOR_COPIES.values).freeze
  SYSTEM_KINDS = %w[password_reset email_change application_registration].freeze
  PROGRAM_KINDS = (BOOKING_KINDS + %w[participant_invitation program_coordinator_invitation booking_invitation
                                      application_draft application_submitted application_accepted
                                      application_declined participation_admission]).freeze
  VENUE_KINDS = (['venue_coordinator_invitation'] + PROGRAM_KINDS).freeze
  KINDS = (SYSTEM_KINDS + VENUE_KINDS).freeze
  SCHEDULED = %w[confirmation_request confirmation_reminder session_reminder coordinator_alert].freeze
  COORDINATOR_ONLY = (%w[attendance_confirmed coordinator_alert application_submitted participation_admission] +
                      COORDINATOR_COPIES.values).freeze
  REQUIRED_LINKS = {
    'password_reset' => %w[reset_url], 'email_change' => %w[confirmation_url],
    'application_registration' => %w[verification_url], 'participant_invitation' => %w[invitation_url],
    'program_coordinator_invitation' => %w[invitation_url], 'venue_coordinator_invitation' => %w[invitation_url],
    'booking_invitation' => %w[booking_url], 'application_draft' => %w[application_url],
    'application_submitted' => %w[review_url], 'application_accepted' => %w[application_url calendar_url],
    'application_declined' => %w[application_url], 'participation_admission' => %w[history_url]
  }.freeze
  BOOKING_PLACEHOLDERS = %w[participant_name program_name venue_name venue_address session_date session_time session_end
                            time_zone previous_session_details session_details attendance_status confirmation_details
                            organizer_contact booking_url confirmation_url rescheduling_deadline].freeze
  COMMON_PLACEHOLDERS = %w[recipient_name recipient_email].freeze
  PROGRAM_PLACEHOLDERS = %w[participant_name program_name venue_name participant_label participant_article
                            regular_schedule].freeze
  EXTRA_PLACEHOLDERS = {
    'program_coordinator_invitation' => %w[target_name coordinator_label],
    'venue_coordinator_invitation' => %w[venue_name target_name coordinator_label],
    'application_draft' => %w[reminder_days], 'participation_admission' => %w[admission_source]
  }.freeze

  def self.base_kind(kind)
    COORDINATOR_COPIES.key(kind) || kind
  end

  def self.placeholders(kind)
    return BOOKING_PLACEHOLDERS if BOOKING_KINDS.include?(kind)

    fields = COMMON_PLACEHOLDERS + EXTRA_PLACEHOLDERS.fetch(kind, []) + REQUIRED_LINKS.fetch(kind, [])
    fields += PROGRAM_PLACEHOLDERS if PROGRAM_KINDS.include?(kind) || kind == 'application_registration'
    fields
  end

  def self.kinds_for(scope)
    return PROGRAM_KINDS if scope.is_a?(Program)
    return VENUE_KINDS if scope.is_a?(Venue)

    KINDS
  end

  def self.defaults(kind)
    { 'enabled' => kind != 'coordinator_alert',
      'timing' => kind == 'confirmation_request' ? 'previous_session_end' : 'days_before',
      'days_before' => kind == 'session_reminder' ? 1 : 5, 'days_after' => 7, 'time' => '12:00' }
  end
end
