# frozen_string_literal: true

class BookingNotificationTiming
  def initialize(booking)
    @booking = booking
    @program = booking.program
  end

  def due_at(kind)
    setting = BookingNotificationSetting.for(@program, kind)
    return previous_session_end if setting.timing == 'previous_session_end'

    local_checkpoint(@booking.date - setting.days_before, setting.time)
  end

  def confirmation_opens_at
    due_at('confirmation_request')
  end

  def fresh?(kind, due)
    return false if kind != 'confirmation_request' && due < @booking.created_at

    [due, @booking.created_at].max.in_time_zone(@booking.time_zone).to_date ==
      Time.current.in_time_zone(@booking.time_zone).to_date
  end

  private

  def previous_session_end
    schedule = previous_schedule
    date = @booking.date - 1
    loop do
      ending = session_end(schedule, date)
      return ending if ending

      date -= 1
    end
  end

  def previous_schedule
    source = @program.dup
    source.id = @program.id
    source.time_zone = @booking.time_zone
    exceptions = ProgramScheduleException.where(program_id: @program.id).to_a
    ProgramSchedule.new(source, from: nil, exceptions: exceptions)
  end

  def session_end(schedule, date)
    return unless schedule.starts_at(date)

    booking = Booking.where(program_id: @program.id, date: date, status: 'confirmed').first
    booking&.ends_at || schedule.ends_at(date, time_zone: @booking.time_zone) ||
      (date + 1).in_time_zone(@booking.time_zone).utc
  rescue ArgumentError
    nil
  end

  def local_checkpoint(date, clock)
    ProgramSchedule.local_start(date, clock, @booking.time_zone)
  rescue ArgumentError
    # Advance a configured clock through the spring-forward gap.
    hour, minute = clock.split(':').map(&:to_i)
    Time.find_zone!(@booking.time_zone).local(date.year, date.month, date.day, hour, minute).utc
  end
end
