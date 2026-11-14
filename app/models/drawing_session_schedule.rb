# frozen_string_literal: true

class DrawingSessionSchedule
  TIME_FORMAT = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/

  def initialize(drawing_session, from: Time.current.in_time_zone(drawing_session.time_zone).to_date)
    @drawing_session = drawing_session
    @from = from
  end

  def exceptions
    @exceptions ||= if @drawing_session.persisted?
                      records = @drawing_session.schedule_exceptions
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

    @drawing_session.start_time if @drawing_session.available_weekdays.include?(date.wday.to_s)
  end

  def starts_at(date)
    clock = time_for(date)
    self.class.local_start(date, clock, @drawing_session.time_zone) if clock
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
