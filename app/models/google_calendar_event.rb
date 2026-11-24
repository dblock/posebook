# frozen_string_literal: true

class GoogleCalendarEvent
  def initialize(booking, connection)
    @booking = booking
    @program = booking.program
    @user = booking.user
    @connection = connection
  end

  def build
    Google::Apis::CalendarV3::Event.new(
      summary: "#{@program.name} - #{@user.name}", status: 'confirmed',
      description: description, location: @program.venue.address,
      start: time(beginning),
      end: time(ending),
      visibility: 'private', guests_can_modify: false, guests_can_invite_others: false,
      guests_can_see_other_guests: true,
      reminders: Google::Apis::CalendarV3::Event::Reminders.new(use_default: false),
      attendees: attendee_emails.map { |email| Google::Apis::CalendarV3::EventAttendee.new(email: email) }
    )
  end

  private

  def beginning
    @booking.scheduled_start - @program.calendar_invitation_lead_minutes.minutes
  end

  def ending
    @booking.scheduled_ends_at || (@booking.scheduled_start + 1.hour)
  end

  def time(value)
    Google::Apis::CalendarV3::EventDateTime.new(date_time: value.iso8601, time_zone: @booking.time_zone)
  end

  def description
    [
      'Private booking details. Do not share this event or make the calendar public.',
      program_start_details,
      *venue_details,
      "Name: #{@user.name}", "Public name: #{public_name}",
      "Email: #{@user.email}", "Phone: #{@user.display_phone}",
      *instagram_details,
      "Posebook: #{program_link}"
    ].compact.join("\n")
  end

  def program_start_details
    return if @program.calendar_invitation_lead_minutes.zero?

    start = @booking.scheduled_start.in_time_zone(@booking.time_zone)
    "#{@program.program_label.titleize} starts: #{start.strftime('%A, %B %-d, %Y at %-I:%M %p %Z')}"
  end

  def venue_details
    venue = @program.venue
    ["Venue: #{venue.name}", "Address: #{venue.address}", "Google Maps: #{venue.google_maps_location_url}"]
  end

  def program_link
    Rails.application.routes.url_helpers.calendar_program_url(
      @program, month: @booking.date.strftime('%Y-%m'), **Rails.application.config.action_mailer.default_url_options
    )
  end

  def instagram_details
    handle = membership ? membership.participant_instagram_handle : @user.public_instagram_handle
    ["Instagram tagging: #{handle.present? ? 'Yes' : 'No'}", ("Instagram: @#{handle}" if handle.present?)]
  end

  def attendee_emails
    User.active.where(:id.in => organizer_ids).pluck(:email).push(@user.email).uniq.sort
  end

  def organizer_ids
    @program.memberships.coordinators.distinct(:user_id) +
      @program.venue.memberships.coordinators.distinct(:user_id) + [@connection.connected_by_id]
  end

  def public_name
    membership ? membership.participant_public_name : @user.public_name
  end

  def membership
    return @membership if defined?(@membership)

    @membership = ProgramMembership.where(program_id: @program.id, user_id: @user.id).first
  end
end
