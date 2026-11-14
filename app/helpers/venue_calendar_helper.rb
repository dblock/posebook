# frozen_string_literal: true

module VenueCalendarHelper
  def booking_model_name(model, manager: false)
    manager && model.public_profile_private? ? model.name : model.public_name
  end

  def venue_organizer_contacts(venue)
    ids = venue.memberships.schedule_managers.distinct(:user_id)
    User.active.where(:id.in => ids).order_by(name: :asc)
  end

  def calendar_access_context(public_view, manager:, venue:, booking:)
    return "public:#{current_user&.id || 'guest'}" if public_view

    "#{manager ? 'manager' : 'model'}:#{current_user.id}:#{current_user.system_admin?}:" \
      "#{venue.schedule_revision}:#{booking&.confirmation_open?}:#{booking&.rescheduling_locked?}:" \
      "#{current_user.gender}"
  end

  def calendar_day_empty?(calendar, date)
    date < calendar.today && !calendar.displayed_bookings[date] && !calendar.session_on?(date)
  end

  def calendar_day_reason(calendar, date, public_view:, manager: false)
    return 'Past Session' if date < calendar.today
    return 'Future' if calendar_future_placeholder?(calendar, date, manager: manager)

    reason = calendar.blocked_reason(date)
    return 'No Session' if reason == 'Not a posing day'
    return 'Closed' if public_view && reason&.start_with?('Closed:')

    reason
  end

  def calendar_future_placeholder?(calendar, date, manager:)
    date > calendar.last_date || (!manager && date.beginning_of_month != calendar.month)
  end

  def calendar_day_label(booking, reason)
    return booking ? booking.display_status : reason if reason == 'Past Session'
    return reason if ['No Session', 'Future'].include?(reason)
    return 'Booked' if booking

    reason ? 'Blocked' : 'Available'
  end

  def calendar_day_class(booking, reason)
    return 'booked' if booking

    reason ? 'blocked' : 'available'
  end

  def venue_schedule_summary(venue)
    weekdays = venue.available_weekdays.sort_by(&:to_i).map { |day| Date::DAYNAMES[day.to_i] }.to_sentence
    "#{weekdays} at #{drawing_time(venue.start_time)} (#{venue.time_zone})"
  end

  def drawing_time(clock)
    DateTime.strptime(clock, '%H:%M').strftime('%-I:%M %p')
  end

  def booking_time(booking)
    booking.scheduled_start.in_time_zone(booking.time_zone).strftime('%-I:%M %p %Z')
  end

  def calendar_time(calendar, date)
    booking = calendar.displayed_bookings[date]
    return booking.scheduled_start.in_time_zone(calendar.venue.time_zone).strftime('%-I:%M %p') if booking

    clock = calendar.schedule.time_for(date)
    drawing_time(clock) if clock
  end

  def calendar_month_path(calendar, month, changing_booking = nil)
    options = { month: month.strftime('%Y-%m') }
    if changing_booking
      edit_venue_model_booking_path(calendar.venue, changing_booking, **options)
    else
      venue_path(calendar.venue, **options)
    end
  end
end
