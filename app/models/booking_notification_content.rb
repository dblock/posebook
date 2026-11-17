# frozen_string_literal: true

class BookingNotificationContent
  def initialize(booking, previous: nil, previous_location: nil)
    @booking = booking
    @program = booking.program
    @previous = previous
    @previous_location = previous_location
  end

  def values
    session_values.merge(identity_values).merge(
      'previous_session_details' => @previous ? details(@previous) : previous_time_details,
      'attendance_status' => attendance_status, 'confirmation_details' => confirmation_details,
      'booking_url' => booking_url, 'confirmation_url' => booking_url,
      'rescheduling_deadline' => (@booking.date - 5).strftime('%A, %B %-d, %Y')
    )
  end

  private

  def identity_values
    { 'participant_name' => @booking.user.name, 'program_name' => @program.name,
      'organizer_contact' => BookingNotification.coordinators(@program).map do |user|
        "#{user.name}: #{user.email}"
      end.join(', ') }
  end

  def session_values
    {
      'venue_name' => @program.venue.name, 'venue_address' => @program.venue.address,
      'session_date' => @booking.date.strftime('%A, %B %-d, %Y'),
      'session_time' => local_time(@booking.scheduled_start),
      'session_end' => @booking.scheduled_ends_at ? local_time(@booking.scheduled_ends_at) : 'End time not specified',
      'time_zone' => @booking.time_zone, 'session_details' => details(@booking)
    }
  end

  def attendance_status
    @booking.attendance_confirmed? ? 'Your attendance is confirmed.' : 'Attendance is not confirmed.'
  end

  def booking_url
    Rails.application.routes.url_helpers.calendar_program_url(
      @program, **Rails.application.config.action_mailer.default_url_options
    )
  end

  def details(booking, location = @program.venue.attributes)
    ending = booking.scheduled_ends_at ? " to #{local_time(booking.scheduled_ends_at)}" : ''
    "#{booking.date.strftime('%A, %B %-d, %Y')} at #{local_time(booking.scheduled_start)}#{ending} " \
      "(#{booking.time_zone})\n#{location.fetch('name')}\n#{location.fetch('address')}"
  end

  def local_time(time)
    time.in_time_zone(@booking.time_zone).strftime('%-I:%M %p %Z')
  end

  def previous_time_details
    return details(@booking, @previous_location) if @previous_location

    change = @booking.time_changes.last
    return 'Not applicable' unless change

    change['from'].in_time_zone(@booking.time_zone).strftime('%A, %B %-d, %Y at %-I:%M %p %Z')
  end

  def confirmation_details
    return 'Your attendance is confirmed.' if @booking.attendance_confirmed?
    return 'Please confirm your attendance using the booking link.' if @booking.confirmation_open?

    opens = BookingNotificationTiming.new(@booking).confirmation_opens_at.in_time_zone(@booking.time_zone)
    "Attendance confirmation opens #{opens.strftime('%A, %B %-d, %Y at %-I:%M %p %Z')}."
  end
end
