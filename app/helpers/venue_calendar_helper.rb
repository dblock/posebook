# frozen_string_literal: true

module VenueCalendarHelper
  def calendar_month_path(calendar, month, changing_booking = nil)
    options = { month: month.strftime('%Y-%m') }
    if changing_booking
      edit_venue_model_booking_path(calendar.venue, changing_booking, **options)
    else
      venue_path(calendar.venue, **options)
    end
  end
end
