# frozen_string_literal: true

class ProgramSettingsUpdate
  include ProgramScheduleLock

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def call(attributes)
    with_schedule_lock do |session|
      previous_time = @program.start_time
      @program.update!(attributes)
      update_booking_times(session) if previous_time != @program.start_time
    end
    @program
  rescue Mongoid::Errors::Validations => e
    e.document
  rescue ArgumentError => e
    @program.errors.add(:start_time, e.message)
    @program
  end

  private

  def update_booking_times(session)
    schedule = ProgramSchedule.new(@program)
    records = Booking.upcoming.where(program_id: @program.id)
    records.each do |booking|
      next if schedule.exceptions[booking.date]&.mode.in?(%w[open closed])

      start = ProgramSchedule.local_start(booking.date, @program.start_time, booking.time_zone)
      booking.change_time!(start, 'Regular start time changed.', @user, session: session)
    end
  end
end
