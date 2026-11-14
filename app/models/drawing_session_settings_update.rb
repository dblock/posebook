# frozen_string_literal: true

class DrawingSessionSettingsUpdate
  include DrawingSessionScheduleLock

  def initialize(drawing_session:, user:)
    @drawing_session = drawing_session
    @user = user
  end

  def call(attributes)
    with_schedule_lock do |session|
      previous_time = @drawing_session.start_time
      @drawing_session.update!(attributes)
      update_booking_times(session) if previous_time != @drawing_session.start_time
    end
    @drawing_session
  rescue Mongoid::Errors::Validations => e
    e.document
  rescue ArgumentError => e
    @drawing_session.errors.add(:start_time, e.message)
    @drawing_session
  end

  private

  def update_booking_times(session)
    schedule = DrawingSessionSchedule.new(@drawing_session)
    records = ModelBooking.upcoming.where(drawing_session_id: @drawing_session.id)
    records.each do |booking|
      next if schedule.exceptions[booking.date]&.mode.in?(%w[open closed])

      start = DrawingSessionSchedule.local_start(booking.date, @drawing_session.start_time, booking.time_zone)
      booking.change_time!(start, 'Regular drawing time changed.', @user, session: session)
    end
  end
end
