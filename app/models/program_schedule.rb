# frozen_string_literal: true

class ProgramSchedule
  TIME_FORMAT = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/

  def initialize(program, from: Time.current.in_time_zone(program.time_zone).to_date)
    @program = program
    @from = from
  end

  def exceptions
    @exceptions ||= if @program.persisted?
                      records = @program.schedule_exceptions
                      records = records.where(:date.gte => @from) if @from
                      records.index_by(&:date)
                    else
                      {}
                    end
  end

  def time_for(date)
    exception = exceptions[date]
    return if exception&.mode == 'closed'
    return exception.start_time if exception&.mode == 'open'

    @program.start_time if @program.available_weekdays.include?(date.wday.to_s)
  end

  def starts_at(date)
    clock = time_for(date)
    self.class.local_start(date, clock, @program.time_zone) if clock
  end

  def end_time_for(date)
    exception = exceptions[date]
    return if exception&.mode == 'closed'
    return exception.end_time if exception&.mode == 'open'

    @program.end_time if @program.available_weekdays.include?(date.wday.to_s)
  end

  def ends_at(date, time_zone: @program.time_zone)
    clock = time_for(date)
    ending = end_time_for(date)
    return unless clock && ending

    self.class.local_end(date, clock, ending, time_zone)
  end

  def self.local_end(date, start_clock, end_clock, time_zone)
    raise ArgumentError, 'End time must differ from the start time.' if start_clock == end_clock

    end_date = end_clock < start_clock ? date + 1 : date
    result = local_start(end_date, end_clock, time_zone)
    raise ArgumentError, 'End time must be after the start time.' if result <= local_start(date, start_clock, time_zone)

    result
  rescue ArgumentError => e
    raise ArgumentError, e.message.sub('Start time', 'End time')
  end

  def self.local_start(date, clock, time_zone)
    hour, minute = clock.split(':').map(&:to_i)
    local = Time.utc(date.year, date.month, date.day, hour, minute)
    if TZInfo::Timezone.get(time_zone).periods_for_local(local).empty?
      raise ArgumentError, 'Start time does not exist on this date in this time zone.'
    end

    Time.find_zone!(time_zone).local(date.year, date.month, date.day, hour, minute).utc
  end
end
