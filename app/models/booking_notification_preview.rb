# frozen_string_literal: true

class BookingNotificationPreview
  attr_reader :booking

  def initialize(program, setting, confirmed: false,
                 url_options: Rails.application.config.action_mailer.default_url_options)
    @setting = setting
    @confirmed = confirmed
    @url_options = url_options
    @program = preview_program(program)
    @booking = sample_booking
  end

  def preview_program(program)
    original_id = program.id
    venue = program.venue
    program = program.dup
    program.id = original_id
    program.venue = venue
    settings = { @setting.kind => @setting.attributes.except('kind') }
    program.notification_settings = program.notification_settings.merge(settings)
    program
  end

  def sample_booking
    date = sample_date
    Booking.new(sample_attributes(date))
  end

  def sample_date
    date = Time.current.in_time_zone(@program.time_zone).to_date + 14
    date += 1 until sample_session?(date)
    date
  end

  def sample_session?(date)
    @schedule ||= ProgramSchedule.new(@program)
    start = @schedule.starts_at(date)
    @schedule.ends_at(date) if start
    start.present?
  rescue ArgumentError
    false
  end

  def sample_attributes(date)
    { program: @program, user: User.new(name: 'Alex Example', email: 'alex@example.test'),
      date: date, time_zone: @program.time_zone,
      starts_at: @schedule.starts_at(date), scheduled_ends_at: @schedule.ends_at(date),
      ends_at: (date + 1).in_time_zone(@program.time_zone), created_at: Time.current,
      attendance_confirmed_at: @confirmed ? Time.current : nil }
  end

  def content
    values = BookingNotificationContent.new(booking).values.merge(
      'organizer_contact' => 'Sam Organizer: organizer@example.test or +1 (202) 555-0100',
      'previous_session_details' => "#{(booking.date - 7).strftime('%A, %B %-d, %Y')} at 6:00 PM",
      'booking_url' => booking_url, 'confirmation_url' => booking_url
    )
    @setting.render(values)
  end

  def timing
    return 'Queued immediately after the action' unless BookingNotificationSetting::SCHEDULED.include?(@setting.kind)

    time = BookingNotificationTiming.new(booking).due_at(@setting.kind).in_time_zone(booking.time_zone)
    "#{time.strftime('%A, %B %-d, %Y at %-I:%M %p %Z')} (#{booking.time_zone})"
  end

  def recipient
    return 'Assigned coordinators' if @setting.kind == 'coordinator_alert'
    if BookingNotificationSetting::COORDINATOR_ONLY.include?(@setting.kind)
      return 'Assigned coordinators other than the participant and the person making the change'
    end

    'alex@example.test'
  end

  private

  def booking_url
    Rails.application.routes.url_helpers.calendar_program_url(@program, **@url_options)
  end
end
