# frozen_string_literal: true

module VenueCalendarHelper
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
