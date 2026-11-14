# frozen_string_literal: true

class AttendanceMutation
  include ProgramScheduleLock

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def confirm(id, version:)
    with_schedule_lock do |session|
      unless @user.reload.active? && @program.participant?(@user)
        raise BookingMutation::Invalid,
              @program.message('bookings.participant_required')
      end

      @booking = Booking.where(program_id: @program.id, user_id: @user.id).find(id)
      confirm_booking(session, version)
    end
    @booking
  end

  private

  def confirm_booking(session, version)
    # Repeated positive confirmations are harmless, but never revive a closed booking.
    @booking.assert_version!(@booking.attendance_confirmed? ? @booking.lock_version : version)
    return if @booking.attendance_confirmed?

    unless @booking.confirmation_open?
      raise BookingMutation::Invalid,
            @program.message('bookings.confirmation_unavailable')
    end

    @booking.record_attendance!(true, @user, "I'll be there!", session: session)
  end
end
