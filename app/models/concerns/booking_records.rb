# frozen_string_literal: true

module BookingRecords
  private

  def available_date(value)
    date = Date.iso8601(value.to_s)
    raise BookingMutation::Invalid, I18n.t('bookings.invalid_date') if VenueCalendar.new(@venue).blocked_reason(date)

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
    ModelBooking.create!(venue: @venue, user: user, created_by_id: @user.id, date: date, time_zone: @venue.time_zone,
                         starts_at: VenueSchedule.new(@venue).starts_at(date),
                         ends_at: (date + 1).in_time_zone(@venue.time_zone).utc, previous_booking: previous,
                         gender_override_reason: gender_override_reason)
  end

  def expire_claims
    # Only disposable claims expire; model booking history is never removed.
    ModelBookingClaim.collection.find(venue_id: @venue.id, ends_at: { '$lte' => Time.current }).delete_many
  end
end
