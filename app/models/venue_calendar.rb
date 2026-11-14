# frozen_string_literal: true

class VenueCalendar
  attr_reader :venue, :today, :last_date, :month

  def initialize(venue, month: nil)
    @venue = venue
    @today = Time.current.in_time_zone(venue.time_zone).to_date
    @last_date = today.advance(months: venue.booking_horizon_months)
    @month = selected_month(month)
  end

  def weeks
    (month.beginning_of_week(:sunday)..month.end_of_month.end_of_week(:sunday)).to_a.each_slice(7)
  end

  def blocked_reason(date)
    return 'Outside booking window' unless date.between?(today, last_date)
    return 'Not a posing day' unless venue.available_weekdays.include?(date.wday.to_s)

    nil
  end

  def bookings
    @bookings ||= ModelBooking.upcoming.where(venue_id: venue.id).index_by(&:date)
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
