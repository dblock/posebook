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
      "#{venue.schedule_revision}:#{booking&.confirmation_open?}:#{booking&.rescheduling_locked?}"
  end

  def calendar_day_reason(calendar, date, public_view:)
    reason = date.beginning_of_month == calendar.month ? calendar.blocked_reason(date) : 'Outside displayed month'
    return 'Closed' if public_view && reason&.start_with?('Closed:')

    reason
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
    booking = calendar.bookings[date]
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
