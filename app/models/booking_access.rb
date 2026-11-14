# frozen_string_literal: true

class BookingAccess
  def initialize(membership, booking: nil, allowed: nil)
    @membership = membership
    return if allowed.nil?

    # Roster rendering supplies a request-local snapshot; mutations still query live state.
    @booking = booking
    @allowed = allowed
  end

  def paused?
    @membership&.participant_paused
  end

  def participant?
    @membership.present?
  end

  def allowed?
    return @allowed if defined?(@allowed)

    return false unless @membership&.user&.active? && !paused?

    granted_at = invitation_time
    granted_at.present? && !records.exists?(status: 'confirmed', :ends_at.gt => granted_at,
                                            :ends_at.lte => Time.current)
  end

  def booking
    return @booking if defined?(@booking)

    @booking = records.upcoming.first
  end

  def reason
    @membership.program.message(paused? ? 'participant_access.paused' : 'participant_access.invitation_required')
  end

  def status
    return 'Inactive' unless @membership.user.active?
    return 'Paused' if paused?
    return 'Booked' if booking

    allowed? ? 'Invited' : 'Uninvited'
  end

  private

  def invitation_time
    @membership.booking_invited_at || records.order_by(created_at: :desc).first&.created_at
  end

  def records
    Booking.where(program_id: @membership.program_id, user_id: @membership.user_id)
  end
end
