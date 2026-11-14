# frozen_string_literal: true

class ModelAccessMutation
  include VenueScheduleLock

  def initialize(venue:, user:)
    @venue = venue
    @user = user
  end

  def invite(id)
    run(id) do |membership|
      access = ModelBookingAccess.new(membership)
      @invited = membership.user.active? && !access.paused? && !access.booking
      membership.update!(booking_invited_at: Time.current, booking_invited_by_id: @user.id) if @invited
    end
    @membership if @invited
  end

  def pause(id, reason)
    text = reason.is_a?(String) ? reason.strip : ''
    raise BookingMutation::Invalid, I18n.t('model_access.reason_required') if text.empty? || text.length > 200

    run(id) { |membership| membership.update!(model_paused: true, model_pause_reason: text) }
  end

  def resume(id)
    run(id) { |membership| membership.update!(model_paused: false) }
  end

  private

  def run(id)
    with_schedule_lock do
      raise BookingMutation::Invalid, I18n.t('model_access.forbidden') unless @user.active? && @venue.managed_by?(@user)

      @membership = @venue.memberships.models.find(id)
      yield @membership
    end
    @membership
  end
end
