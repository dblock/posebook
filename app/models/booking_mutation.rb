# frozen_string_literal: true

class BookingMutation
  include VenueScheduleLock

  class Invalid < StandardError; end
  class Conflict < StandardError; end

  def initialize(venue:, user:)
    @venue = venue
    @user = user
  end

  def book(date:)
    run do
      raise Invalid, I18n.t('bookings.already_scheduled') if claims.exists?

      @booking = create_record(available_date(date))
      ModelBookingClaim.create!(venue: @venue, user: @user, model_booking: @booking,
                                date: @booking.date, ends_at: @booking.ends_at)
    end
  end

  def change(booking:, date:, reason:)
    run do |session|
      original = active_booking(booking.id)
      selected = available_date(date)
      raise Invalid, I18n.t('bookings.different_date') if selected == original.date

      original.close!('rescheduled', explanation(reason), @user, session: session)
      @booking = create_record(selected, previous: original)
      claim = claims.find_by(model_booking_id: original.id)
      claim.update!(model_booking: @booking, date: @booking.date, ends_at: @booking.ends_at)
    end
  end

  def cancel(booking:, reason:)
    run(booking_access: false) do |session|
      original = active_booking(booking.id)
      original.close!('canceled', explanation(reason), @user, session: session)
      removed = ModelBookingClaim.collection.find(model_booking_id: original.id).find_one_and_delete(session: session)
      raise Conflict, I18n.t('bookings.conflict') unless removed

      @booking = original.reload
    end
  end

  private

  def run(booking_access: true)
    verify_model!
    expire_claims
    with_schedule_lock do |session|
      check_booking_access!(booking_access)
      yield session
    end
    @booking
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000

    raise Conflict, I18n.t('bookings.conflict')
  end

  def check_booking_access!(required)
    verify_model!
    return unless required

    access = ModelBookingAccess.new(@venue.memberships.models.where(user_id: @user.id).first)
    raise Invalid, access.reason unless access.allowed?
  end

  def verify_model!
    raise Invalid, I18n.t('bookings.model_required') unless @user.active? && @venue.model?(@user)
  end

  def expire_claims
    # Only disposable claims expire; model booking history is never removed.
    ModelBookingClaim.collection.find(venue_id: @venue.id, ends_at: { '$lte' => Time.current }).delete_many
  end

  def claims
    ModelBookingClaim.where(venue_id: @venue.id, user_id: @user.id)
  end

  def active_booking(id)
    ModelBooking.upcoming.where(venue_id: @venue.id, user_id: @user.id).find(id)
  end

  def available_date(value)
    date = Date.iso8601(value.to_s)
    raise Invalid, I18n.t('bookings.invalid_date') if VenueCalendar.new(@venue).blocked_reason(date)

    date
  rescue ArgumentError
    raise Invalid, I18n.t('bookings.invalid_date')
  end

  def explanation(value)
    text = value.is_a?(String) ? value.strip : ''
    raise Invalid, I18n.t('bookings.reason_required') if text.empty? || text.length > 2000

    text
  end

  def create_record(date, previous: nil)
    ModelBooking.create!(venue: @venue, user: @user, date: date, time_zone: @venue.time_zone,
                         starts_at: VenueSchedule.new(@venue).starts_at(date),
                         ends_at: (date + 1).in_time_zone(@venue.time_zone).utc, previous_booking: previous)
  end
end
