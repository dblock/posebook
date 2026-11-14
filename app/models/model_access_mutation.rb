# frozen_string_literal: true

class ModelAccessMutation
  include DrawingSessionScheduleLock

  def initialize(drawing_session:, user:)
    @drawing_session = drawing_session
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
      unless @user.active? && @drawing_session.managed_by?(@user)
        raise BookingMutation::Invalid,
              I18n.t('model_access.forbidden')
      end

      @membership = @drawing_session.memberships.models.find(id)
      yield @membership
    end
    @membership
  end
end
