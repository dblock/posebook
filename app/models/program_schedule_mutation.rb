# frozen_string_literal: true

class ProgramScheduleMutation
  include ProgramScheduleLock

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def call(attributes)
    with_schedule_lock do |session|
      authorize!
      save_exception(attributes)
      update_bookings(session)
    end
    @exception
  rescue Mongoid::Errors::Validations => e
    e.document
  rescue ArgumentError => e
    @exception.errors.add(e.message.start_with?('End time') ? :end_time : :start_time, e.message)
    @exception
  end

  private

  def save_exception(attributes)
    @exception = @program.schedule_exceptions.find_or_initialize_by(date: parse_date(attributes[:date]))
    @exception.assign_attributes(attributes.slice(:mode, :start_time, :end_time, :reason))
    @exception.save!
  end

  def authorize!
    return if @user.active? && @program.managed_by?(@user)

    raise BookingMutation::Invalid,
          'Schedule access is required.'
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def update_bookings(session)
    schedule = ProgramSchedule.new(@program)
    records = Booking.upcoming.where(program_id: @program.id, date: @exception.date)
    records.each do |booking|
      if schedule.time_for(booking.date)
        change_booking_time(booking, schedule, session)
      else
        cancel_booking(booking, session)
      end
    end
  end

  def change_booking_time(booking, schedule, session)
    start = ProgramSchedule.local_start(booking.date, schedule.time_for(booking.date), booking.time_zone)
    ending = schedule.ends_at(booking.date, time_zone: booking.time_zone)
    booking.change_time!(start, @exception.reason, @user, session: session, scheduled_end: ending)
  end

  def cancel_booking(booking, session)
    booking.close!('canceled', @exception.reason, @user, session: session)
    result = BookingClaim.collection.find(booking_id: booking.id).delete_one(session: session)
    raise BookingMutation::Conflict, @program.message('bookings.conflict') unless result.deleted_count == 1
  end
end
