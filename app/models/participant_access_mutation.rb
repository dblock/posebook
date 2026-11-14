# frozen_string_literal: true

class ParticipantAccessMutation
  include ProgramScheduleLock

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def invite(id)
    run(id) do |membership|
      access = BookingAccess.new(membership)
      @invited = membership.user.active? && !access.paused? && !access.booking
      membership.update!(booking_invited_at: Time.current, booking_invited_by_id: @user.id) if @invited
    end
    @membership if @invited
  end

  def pause(id, reason)
    text = reason.is_a?(String) ? reason.strip : ''
    if text.empty? || text.length > 200
      raise BookingMutation::Invalid,
            @program.message('participant_access.reason_required')
    end

    run(id) { |membership| membership.update!(participant_paused: true, participant_pause_reason: text) }
  end

  def resume(id)
    run(id) { |membership| membership.update!(participant_paused: false) }
  end

  private

  def run(id)
    with_schedule_lock do
      unless @user.active? && @program.managed_by?(@user)
        raise BookingMutation::Invalid,
              @program.message('participant_access.forbidden')
      end

      @membership = @program.memberships.participants.find(id)
      yield @membership
    end
    @membership
  end
end
