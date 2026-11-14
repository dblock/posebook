# frozen_string_literal: true

class BookingMutation
  include DrawingSessionScheduleLock
  include BookingRecords

  class Invalid < StandardError; end
  class Conflict < StandardError; end
  class Stale < Conflict; end

  def initialize(drawing_session:, user:)
    @drawing_session = drawing_session
    @user = user
  end

  def book(date:)
    run do
      raise Invalid, I18n.t('bookings.already_scheduled') if claims.exists?

      selected = available_date(date)
      check_gender!(selected)
      @booking = create_record(selected)
      ModelBookingClaim.create!(drawing_session: @drawing_session, user: @user, model_booking: @booking,
                                date: @booking.date, ends_at: @booking.ends_at)
    end
  end

  def change(booking:, date:, reason:, version: booking.lock_version)
    run do |session|
      original = reschedulable_booking(booking.id, version: version)
      selected = rescheduling_date(original, date)
      original.close!('rescheduled', explanation(reason), @user, session: session)
      @booking = create_record(selected, previous: original)
      claim = claims.find_by(model_booking_id: original.id)
      claim.update!(model_booking: @booking, date: @booking.date, ends_at: @booking.ends_at)
    end
  end

  def cancel(booking:, reason:, version: booking.lock_version)
    run(booking_access: false) do |session|
      original = active_booking(booking.id, version: version)
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

    access = ModelBookingAccess.new(@drawing_session.memberships.models.where(user_id: @user.id).first)
    raise Invalid, access.reason unless access.allowed?
  end

  def verify_model!
    raise Invalid, I18n.t('bookings.model_required') unless @user.reload.active? && @drawing_session.model?(@user)
  end

  def check_gender!(date, excluding: nil)
    reason = BookingGenderRule.new(@drawing_session, excluding: excluding).blocked_reason(date, @user)
    raise Invalid, reason if reason
  end

  def rescheduling_date(original, value)
    date = available_date(value, excluding: original.id)
    raise Invalid, I18n.t('bookings.different_date') if date == original.date

    check_gender!(date, excluding: original.id)
    date
  end

  def claims
    ModelBookingClaim.where(drawing_session_id: @drawing_session.id, user_id: @user.id)
  end

  def active_booking(id, version:)
    booking = ModelBooking.where(drawing_session_id: @drawing_session.id, user_id: @user.id).find(id)
    booking.assert_version!(version)
    booking
  end

  def reschedulable_booking(id, version:)
    booking = active_booking(id, version: version)
    raise Invalid, I18n.t('bookings.rescheduling_locked') if booking.rescheduling_locked?

    booking
  end
end
