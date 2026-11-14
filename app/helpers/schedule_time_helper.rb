# frozen_string_literal: true

module ScheduleTimeHelper
  def regular_time_range(program)
    start = format_start_time(program.start_time)
    return start if program.end_time.blank?

    start_minutes = clock_minutes(program.start_time)
    end_minutes = clock_minutes(program.end_time)
    "#{start} - #{format_start_time(program.end_time)}#{' next day' if end_minutes < start_minutes} " \
      "(#{format_duration((end_minutes - start_minutes) % 1440)})"
  end

  def time_range(start, ending, zone: false)
    suffix = ending.to_date > start.to_date ? ' next day' : ''
    zone_name = zone ? " #{ending.strftime('%Z')}" : ''
    "#{start.strftime('%-I:%M %p')} - #{ending.strftime('%-I:%M %p')}#{suffix}#{zone_name} " \
      "(#{format_duration(((ending - start) / 60).to_i)})"
  end

  def format_duration(minutes)
    hours, remainder = minutes.divmod(60)
    [('1 hour' if hours == 1) || ("#{hours} hours" if hours.positive?),
     ("#{remainder} min" if remainder.positive?)].compact.join(' ')
  end

  def clock_minutes(clock)
    hour, minute = clock.split(':').map(&:to_i)
    (hour * 60) + minute
  end
end
