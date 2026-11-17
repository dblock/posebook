# frozen_string_literal: true

class ProgramSettingsUpdate
  include ProgramScheduleLock

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def call(attributes)
    with_schedule_lock do |session|
      authorize!
      @program.update!(merge_settings(attributes))
      update_dependents(session)
    end
    @program
  rescue Mongoid::Errors::Validations => e
    e.document
  rescue ArgumentError => e
    @program.errors.add(e.message.start_with?('End time') ? :end_time : :start_time, e.message)
    @program
  end

  private

  def authorize!
    return if @user.reload.active? && @program.managed_by?(@user)

    raise LocationActivation::Forbidden
  end

  def merge_settings(attributes)
    return attributes unless attributes.key?(:notification_settings)

    attributes.merge(notification_settings: @program.notification_settings.merge(attributes[:notification_settings]))
  end

  def update_dependents(session)
    update_booking_times(session) if @program.saved_change_to_start_time? || @program.saved_change_to_end_time?
    enqueue_calendar_changes(session) if @program.saved_change_to_calendar_invitation_lead_minutes?
  end

  def enqueue_calendar_changes(session)
    records = Booking.upcoming.where(program_id: @program.id)
    records.each do |booking|
      GoogleCalendarSync.enqueue(booking, session: session)
    end
  end

  def update_booking_times(session)
    schedule = ProgramSchedule.new(@program)
    records = Booking.upcoming.where(program_id: @program.id)
    records.each do |booking|
      next if schedule.exceptions[booking.date]&.mode.in?(%w[open closed])

      update_booking_time(booking, session)
    end
  end

  def update_booking_time(booking, session)
    start = ProgramSchedule.local_start(booking.date, @program.start_time, booking.time_zone)
    ending = if @program.end_time
               ProgramSchedule.local_end(booking.date, @program.start_time, @program.end_time, booking.time_zone)
             end
    reason = @program.saved_change_to_start_time? ? 'Regular start time changed.' : 'Regular end time changed.'
    booking.change_time!(start, reason, @user, session: session, scheduled_end: ending)
  end
end
