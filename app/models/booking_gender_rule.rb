# frozen_string_literal: true

class BookingGenderRule
  def initialize(drawing_session, excluding: nil)
    @drawing_session = drawing_session
    @excluding = excluding
    @schedule = DrawingSessionSchedule.new(drawing_session, from: nil)
    @bookings = {}
  end

  def blocked_reason(date, user)
    return I18n.t('bookings.gender_required') if user.gender.blank?
    return unless @drawing_session.no_consecutive_genders.include?(user.gender)

    dates = [-1, 1].map { |direction| adjacent_date(date, direction) }
    return unless bookings_on(dates).any? { |booking| booking.user.gender == user.gender }

    I18n.t('bookings.gender_restricted')
  end

  private

  def adjacent_date(date, direction)
    candidate = date + direction
    candidate += direction until scheduled?(candidate)
    candidate
  end

  def scheduled?(date)
    @schedule.starts_at(date).present?
  rescue ArgumentError
    false
  end

  def bookings_on(dates)
    missing = dates - @bookings.keys
    @bookings.merge!(missing.index_with(nil))
    records = ModelBooking.where(drawing_session_id: @drawing_session.id, status: 'confirmed', :id.ne => @excluding,
                                 :date.in => missing)
    @bookings.merge!(records.includes(:user).index_by(&:date)) if missing.any?
    @bookings.values_at(*dates).compact
  end
end
