# frozen_string_literal: true

module BookingRecords
  private

  def available_date(value, excluding: nil)
    date = Date.iso8601(value.to_s)
    if ProgramCalendar.new(@program).blocked_reason(date)
      raise BookingMutation::Invalid,
            @program.message('bookings.invalid_date')
    end

    claims = BookingClaim.where(program_id: @program.id, date: date)
    claims = claims.where(:booking_id.ne => excluding) if excluding
    raise BookingMutation::Conflict, @program.message('bookings.date_taken') if claims.exists?

    date
  rescue ArgumentError
    raise BookingMutation::Invalid, @program.message('bookings.invalid_date')
  end

  def explanation(value)
    text = value.is_a?(String) ? value.strip : ''
    raise BookingMutation::Invalid, @program.message('bookings.reason_required') if text.empty? || text.length > 2000

    text
  end

  def create_record(date, previous: nil, user: @user, gender_override_reason: nil)
    Booking.create!(
      program: @program, user: user, created_by_id: @user.id,
      date: date, time_zone: @program.time_zone,
      starts_at: ProgramSchedule.new(@program).starts_at(date),
      ends_at: (date + 1).in_time_zone(@program.time_zone).utc, previous_booking: previous,
      gender_override_reason: gender_override_reason
    )
  end

  def expire_claims
    # Only disposable claims expire; participant booking history is never removed.
    BookingClaim.collection.find(program_id: @program.id,
                                 ends_at: { '$lte' => Time.current }).delete_many
  end
end
