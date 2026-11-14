# frozen_string_literal: true

module BookingRecords
  private

  def available_date(value, excluding: nil)
    date = Date.iso8601(value.to_s)
    if DrawingSessionCalendar.new(@drawing_session).blocked_reason(date)
      raise BookingMutation::Invalid,
            I18n.t('bookings.invalid_date')
    end

    claims = ModelBookingClaim.where(drawing_session_id: @drawing_session.id, date: date)
    claims = claims.where(:model_booking_id.ne => excluding) if excluding
    raise BookingMutation::Conflict, I18n.t('bookings.date_taken') if claims.exists?

    date
  rescue ArgumentError
    raise BookingMutation::Invalid, I18n.t('bookings.invalid_date')
  end

  def explanation(value)
    text = value.is_a?(String) ? value.strip : ''
    raise BookingMutation::Invalid, I18n.t('bookings.reason_required') if text.empty? || text.length > 2000

    text
  end

  def create_record(date, previous: nil, user: @user, gender_override_reason: nil)
    ModelBooking.create!(
      drawing_session: @drawing_session, user: user, created_by_id: @user.id,
      date: date, time_zone: @drawing_session.time_zone,
      starts_at: DrawingSessionSchedule.new(@drawing_session).starts_at(date),
      ends_at: (date + 1).in_time_zone(@drawing_session.time_zone).utc, previous_booking: previous,
      gender_override_reason: gender_override_reason
    )
  end

  def expire_claims
    # Only disposable claims expire; model booking history is never removed.
    ModelBookingClaim.collection.find(drawing_session_id: @drawing_session.id,
                                      ends_at: { '$lte' => Time.current }).delete_many
  end
end
