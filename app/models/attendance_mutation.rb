# frozen_string_literal: true

class AttendanceMutation
  include VenueScheduleLock

  def initialize(venue:, user:)
    @venue = venue
    @user = user
  end

  def confirm(id, version:)
    with_schedule_lock do |session|
      unless @user.reload.active? && @venue.model?(@user)
        raise BookingMutation::Invalid,
              I18n.t('bookings.model_required')
      end

      @booking = ModelBooking.where(venue_id: @venue.id, user_id: @user.id).find(id)
      confirm_booking(session, version)
    end
    @booking
  end

  private

  def confirm_booking(session, version)
    # Repeated positive confirmations are harmless, but never revive a closed booking.
    @booking.assert_version!(@booking.attendance_confirmed? ? @booking.lock_version : version)
    return if @booking.attendance_confirmed?

    raise BookingMutation::Invalid, I18n.t('bookings.confirmation_unavailable') unless @booking.confirmation_open?

    @booking.record_attendance!(true, @user, "I'll be there!", session: session)
  end
end
