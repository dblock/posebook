# frozen_string_literal: true

class ModelBookingAccess
  def initialize(membership)
    @membership = membership
  end

  def paused?
    @membership&.model_paused
  end

  def model?
    @membership.present?
  end

  def allowed?
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
    I18n.t(paused? ? 'model_access.paused' : 'model_access.invitation_required')
  end

  def status
    return 'Inactive account' unless @membership.user.active?
    return 'Paused' if paused?
    return "Booked: #{booking.date.iso8601}" if booking

    allowed? ? 'Invited to book' : 'Invitation required'
  end

  private

  def invitation_time
    @membership.booking_invited_at || records.order_by(created_at: :desc).first&.created_at
  end

  def records
    ModelBooking.where(venue_id: @membership.venue_id, user_id: @membership.user_id)
  end
end
