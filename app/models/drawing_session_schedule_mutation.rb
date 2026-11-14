# frozen_string_literal: true

class DrawingSessionScheduleMutation
  include DrawingSessionScheduleLock

  def initialize(drawing_session:, user:)
    @drawing_session = drawing_session
    @user = user
  end

  def call(attributes)
    with_schedule_lock do |session|
      authorize!
      @exception = @drawing_session.schedule_exceptions.find_or_initialize_by(date: parse_date(attributes[:date]))
      @exception.assign_attributes(attributes.slice(:mode, :start_time, :reason))
      @exception.save!
      update_bookings(session)
    end
    @exception
  rescue Mongoid::Errors::Validations => e
    e.document
  end

  private

  def authorize!
    return if @user.active? && @drawing_session.managed_by?(@user)

    raise BookingMutation::Invalid,
          'Schedule access is required.'
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def update_bookings(session)
    schedule = DrawingSessionSchedule.new(@drawing_session)
    records = ModelBooking.upcoming.where(drawing_session_id: @drawing_session.id, date: @exception.date)
    records.each do |booking|
      if schedule.time_for(booking.date)
        booking.change_time!(schedule.starts_at(booking.date), @exception.reason, @user, session: session)
      else
        cancel_booking(booking, session)
      end
    end
  end

  def cancel_booking(booking, session)
    booking.close!('canceled', @exception.reason, @user, session: session)
    result = ModelBookingClaim.collection.find(model_booking_id: booking.id).delete_one(session: session)
    raise BookingMutation::Conflict, I18n.t('bookings.conflict') unless result.deleted_count == 1
  end
end
