# frozen_string_literal: true

class BookingNotificationEligibility
  def initialize(notification)
    @notice = notification
    @booking = Booking.where(id: notification.booking_id).first
    @user = User.active.where(id: notification.recipient_id).first
    @kind = notification.kind
  end

  def allowed?
    return false unless available?
    return false unless authorized_recipient? && source_current?

    !@notice.scheduled? || scheduled_current?
  end

  private

  def available?
    @booking && @user && NotificationPreferences.allowed?(@user, @kind) && @notice.expires_at > Time.current &&
      BookingNotificationSetting.for(@booking.program, @kind).enabled
  end

  def authorized_recipient?
    participant = @booking.user
    return false unless participant.active? && @booking.program.participant?(participant)
    return coordinator? if BookingNotificationSetting::COORDINATOR_ONLY.include?(@kind) || @user.id != participant.id

    !@notice.scheduled? || @user.booking_reminders_enabled?
  end

  def coordinator?
    BookingNotification.coordinators(@booking.program).any? { |manager| manager.id == @user.id }
  end

  def source_current?
    return @booking.status.in?(%w[canceled rescheduled]) if @kind == 'booking_canceled'
    return false unless same_session?
    return @booking.attendance_confirmed? if @kind == 'attendance_confirmed'

    @kind.in?(%w[booking_created booking_changed session_reminder]) || !@booking.attendance_confirmed?
  end

  def same_session?
    return false unless @booking.status == 'confirmed' && @notice.signature == BookingNotification.signature(@booking)

    !@kind.start_with?('attendance_') || @notice.attendance_revision == @booking.attendance_changes.size
  end

  def scheduled_current?
    return false if @kind != 'session_reminder' && !@booking.confirmation_open?
    return false if participant_message_sent_today?

    timing = BookingNotificationTiming.new(@booking)
    due = timing.due_at(@kind)
    due == @notice.scheduled_for && due <= Time.current && timing.fresh?(@kind, due)
  end

  def participant_message_sent_today?
    return false if @kind == 'coordinator_alert' || @user.id != @booking.user_id

    today = Time.current.in_time_zone(@booking.time_zone).beginning_of_day
    BookingNotification.exists?(booking_id: @booking.id, recipient_id: @user.id, state: 'sent',
                                :sent_at.gte => today, :id.ne => @notice.id)
  end
end
