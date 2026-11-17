# frozen_string_literal: true

module ProgramCalendarHelper
  include ScheduleTimeHelper

  def booking_participant_name(participant, membership = nil, manager: false)
    display_name = membership&.display_name_override || participant.display_name
    return participant.name if manager && display_name.blank?

    participant.active? && display_name.present? ? display_name : 'To be announced'
  end

  def booking_participant_instagram_handle(participant, membership = nil)
    participant.public_instagram_handle unless membership&.instagram_hidden?
  end

  def program_organizer_contacts(program)
    return participant_dashboard.organizer_contacts_for(program.id) if respond_to?(:participant_dashboard)

    ids = program.memberships.coordinators.distinct(:user_id)
    User.active.where(:id.in => ids).order_by(name: :asc)
  end

  def calendar_access_context(public_view, manager:, program:, booking:)
    return "public:#{current_user&.id || 'guest'}" if public_view

    "#{manager ? 'manager' : 'participant'}:#{current_user.id}:#{current_user.system_admin?}:" \
      "#{program.schedule_revision}:#{booking&.confirmation_open?}:#{booking&.rescheduling_locked?}:" \
      "#{current_user.gender}:#{program.booking_active?}"
  end

  def calendar_day_empty?(calendar, date)
    date < calendar.today && !calendar.displayed_bookings[date] && !calendar.session_on?(date)
  end

  def calendar_day_reason(calendar, date, public_view:, manager: false)
    return "Past #{calendar.program.program_label.titleize}" if date < calendar.today
    return 'Future' if calendar_future_placeholder?(calendar, date, manager: manager)

    reason = calendar.blocked_reason(date)
    return "No #{calendar.program.program_label.titleize}" if reason == 'Not a scheduled day'
    return 'Closed' if public_view && reason&.start_with?('Closed:')

    reason
  end

  def calendar_future_placeholder?(calendar, date, manager:)
    date > calendar.last_date || (!manager && date.beginning_of_month > calendar.month)
  end

  def calendar_day_label(booking, reason)
    return past_booking_label(booking) if reason&.start_with?('Past ')
    return 'Unavailable' if reason&.start_with?('No ')
    return reason if reason == 'Future'
    return booking.display_status if booking

    reason ? 'Blocked' : 'Available'
  end

  def past_booking_label(booking)
    booking ? booking.display_status : 'Past'
  end

  def calendar_day_class(booking, reason)
    return 'booked' if booking

    reason ? 'blocked' : 'available'
  end

  def program_schedule_summary(program)
    weekdays = program.available_weekdays.sort_by(&:to_i).map { |day| Date::DAYNAMES[day.to_i] }.to_sentence
    "#{weekdays} at #{regular_time_range(program)} (#{program.time_zone})"
  end

  def format_start_time(clock)
    DateTime.strptime(clock, '%H:%M').strftime('%-I:%M %p')
  end

  def booking_countdown(booking)
    days = (booking.date - Time.current.in_time_zone(booking.time_zone).to_date).to_i
    return 'Today' if days <= 0
    return 'Tomorrow' if days == 1

    "In #{days} days"
  end

  def booking_time(booking)
    start = booking.scheduled_start.in_time_zone(booking.time_zone)
    return start.strftime('%-I:%M %p %Z') unless booking.scheduled_ends_at

    time_range(start, booking.scheduled_ends_at.in_time_zone(booking.time_zone), zone: true)
  end

  def calendar_time(calendar, date)
    booking = calendar.displayed_bookings[date]
    return calendar_booking_time(booking) if booking

    scheduled_calendar_time(calendar, date)
  end

  def scheduled_calendar_time(calendar, date)
    clock = calendar.schedule.time_for(date)
    return unless clock

    start = calendar.starts_at(date)
    ending = calendar.ends_at(date)
    return format_start_time(clock) unless ending

    time_range(start.in_time_zone(calendar.program.time_zone), ending.in_time_zone(calendar.program.time_zone))
  rescue ArgumentError
    nil
  end

  def calendar_booking_time(booking)
    start = booking.scheduled_start.in_time_zone(booking.time_zone)
    return start.strftime('%-I:%M %p') unless booking.scheduled_ends_at

    time_range(start, booking.scheduled_ends_at.in_time_zone(booking.time_zone))
  end

  def calendar_month_path(calendar, month, changing_booking = nil)
    options = { month: month.strftime('%Y-%m') }
    if changing_booking
      edit_program_booking_path(calendar.program, changing_booking, **options)
    else
      calendar_program_path(calendar.program, **options)
    end
  end
end
