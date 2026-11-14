# frozen_string_literal: true

class VenueCalendar
  attr_reader :venue, :today, :last_date, :month, :schedule

  def initialize(venue, month: nil)
    @venue = venue
    @today = Time.current.in_time_zone(venue.time_zone).to_date
    @last_date = today.advance(months: venue.booking_horizon_months)
    @month = selected_month(month)
    @schedule = VenueSchedule.new(venue)
  end

  def weeks
    (month.beginning_of_week(:sunday)..month.end_of_month.end_of_week(:sunday)).to_a.each_slice(7)
  end

  def blocked_reason(date)
    return 'Outside booking window' unless date.between?(today, last_date)

    exception = schedule.exceptions[date]
    return "Closed: #{exception.reason}" if exception&.mode == 'closed'
    return 'Not a posing day' unless schedule.time_for(date)

    return 'Drawing has already started' if schedule.starts_at(date) <= Time.current

    nil
  rescue ArgumentError
    'Start time unavailable because of daylight saving'
  end

  def bookings
    @bookings ||= ModelBooking.upcoming.where(venue_id: venue.id).includes(:user).index_by(&:date)
  end

  def current_booking(user)
    bookings.values.find { |booking| booking.user_id == user.id }
  end

  def history_for(user)
    records = ModelBooking.where(venue_id: venue.id)
    records = records.where(user_id: user.id) unless venue.managed_by?(user)
    records.order_by(date: :desc, created_at: :desc).includes(:user, :previous_booking)
  end

  private

  def selected_month(value)
    candidate = Date.iso8601("#{value}-01")
    candidate.between?(today.beginning_of_month, last_date.beginning_of_month) ? candidate : today.beginning_of_month
  rescue ArgumentError
    today.beginning_of_month
  end
end
