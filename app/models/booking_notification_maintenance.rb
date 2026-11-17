# frozen_string_literal: true

class BookingNotificationMaintenance
  include ProgramScheduleLock

  def self.run
    bookings = Booking.upcoming.where(:starts_at.gt => Time.current)
    bookings.each { |booking| new(booking).schedule }
    pending = BookingNotification.where(state: 'pending')
    pending.each(&:queue)
  end

  def initialize(booking)
    @booking = booking
    @program = booking.program
  end

  def schedule
    return if due_kinds.empty?

    with_schedule_lock do
      @booking.reload
      @booking.program = @program
      next unless @booking.status == 'confirmed' && @booking.scheduled_start > Time.current

      due_kinds.each do |kind|
        due = BookingNotificationTiming.new(@booking).due_at(kind)
        key = "#{BookingNotification.signature(@booking)}:#{due.to_i}"
        BookingNotification.record(@booking, kind, key: key, scheduled_for: due)
      end
    end
  end

  private

  def due_kinds
    kinds = eligible_kinds
    kinds -= %w[confirmation_request] if kinds.include?('confirmation_reminder')
    kinds -= %w[confirmation_request confirmation_reminder] if kinds.include?('session_reminder')
    kinds -= %w[confirmation_request confirmation_reminder session_reminder] if participant_notice_today?
    kinds
  end

  def eligible_kinds
    timing = BookingNotificationTiming.new(@booking)
    kinds = BookingNotificationSetting::SCHEDULED.select do |kind|
      due = timing.due_at(kind)
      due?(kind, due, timing)
    end
    kinds -= %w[confirmation_request confirmation_reminder coordinator_alert] if @booking.attendance_confirmed?
    kinds -= %w[confirmation_request confirmation_reminder coordinator_alert] unless @booking.confirmation_open?
    kinds
  end

  def due?(kind, due, timing)
    return false unless BookingNotificationSetting.for(@program, kind).enabled && due <= Time.current
    return false unless timing.fresh?(kind, due)

    key = "#{@booking.id}:#{kind}:#{BookingNotification.signature(@booking)}:#{due.to_i}"
    !BookingNotification.exists?(event_key: key)
  end

  def participant_notice_today?
    today = Time.current.in_time_zone(@booking.time_zone).beginning_of_day
    records = BookingNotification.where(booking_id: @booking.id, recipient_id: @booking.user_id,
                                        :kind.in => %w[booking_created booking_changed attendance_cleared
                                                       confirmation_request confirmation_reminder session_reminder],
                                        :state.in => %w[pending queued sent failed])
    records.any_of({ :created_at.gte => today }, { :sent_at.gte => today }).exists?
  end
end
