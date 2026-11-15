# frozen_string_literal: true

class ProgramCalendar
  attr_reader :program, :today, :last_date, :month, :schedule

  def initialize(program, month: nil)
    @program = program
    @today = Time.current.in_time_zone(program.time_zone).to_date
    @last_date = today.advance(months: program.booking_horizon_months)
    @month = selected_month(month)
    @schedule = ProgramSchedule.new(program, from: date_range.begin)
    @starts = {}
    @ends = {}
  end

  def weeks
    date_range.to_a.each_slice(7)
  end

  def date_range
    month.beginning_of_week(:sunday)..month.end_of_month.end_of_week(:sunday)
  end

  def session_on?(date)
    start = starts_at(date)
    ends_at(date) if start
    start.present?
  rescue ArgumentError
    false
  end

  def starts_at(date)
    @starts.fetch(date) { @starts[date] = schedule.starts_at(date) }
  end

  def next_session_date
    (today..last_date).find { |date| session_on?(date) && starts_at(date) > Time.current }
  end

  def next_session
    date = next_session_date
    booking = program.bookings.where(date: date, status: 'confirmed').includes(:user).first if date
    [date, booking]
  end

  def ends_at(date)
    @ends.fetch(date) { @ends[date] = schedule.ends_at(date) }
  end

  def displayed_bookings
    @displayed_bookings ||= Booking.where(program_id: program.id, status: 'confirmed',
                                          :date.gte => date_range.begin, :date.lte => date_range.end)
                                   .includes(:user).index_by(&:date)
  end

  def blocked_reason(date)
    return 'Inactive' unless program.booking_active?

    return 'Outside booking window' unless date.between?(today, last_date)

    exception = schedule.exceptions[date]
    return "Closed: #{exception.reason}" if exception&.mode == 'closed'
    return 'Not a scheduled day' unless schedule.time_for(date)

    schedule_blocked_reason(date)
  end

  def bookings
    @bookings ||= Booking.upcoming.where(program_id: program.id).includes(:user).index_by(&:date)
  end

  def current_booking(user)
    bookings.values.find { |booking| booking.user_id == user.id }
  end

  def gender_blocked_reason(date, user, excluding: nil)
    @gender_rule ||= BookingGenderRule.new(program, excluding: excluding,
                                                    bookings: date_range.index_with { |day| displayed_bookings[day] })
    'Blocked' if @gender_rule.evaluate(date, user)
  end

  def history_for(user)
    records = Booking.where(program_id: program.id)
    records = records.where(user_id: user.id) unless program.managed_by?(user)
    records.order_by(date: :desc, created_at: :desc).includes(:user, :previous_booking)
  end

  private

  def schedule_blocked_reason(date)
    @program.message('programs.started') if schedule_start(date) <= Time.current
  rescue ArgumentError => e
    "#{e.message.start_with?('End time') ? 'End' : 'Start'} time unavailable because of daylight saving"
  end

  def schedule_start(date)
    start = starts_at(date)
    ends_at(date)
    start
  end

  def selected_month(value)
    candidate = Date.iso8601("#{value}-01")
    candidate.between?(today.beginning_of_month, last_date.beginning_of_month) ? candidate : today.beginning_of_month
  rescue ArgumentError
    today.beginning_of_month
  end
end
