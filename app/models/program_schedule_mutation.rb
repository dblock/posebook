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
      @exception = @program.schedule_exceptions.find_or_initialize_by(date: parse_date(attributes[:date]))
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
        booking.change_time!(schedule.starts_at(booking.date), @exception.reason, @user, session: session)
      else
        cancel_booking(booking, session)
      end
    end
  end

  def cancel_booking(booking, session)
    booking.close!('canceled', @exception.reason, @user, session: session)
    result = BookingClaim.collection.find(booking_id: booking.id).delete_one(session: session)
    raise BookingMutation::Conflict, @program.message('bookings.conflict') unless result.deleted_count == 1
  end
end
