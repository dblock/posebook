# frozen_string_literal: true

module GoogleCalendarHelper
  def preload_google_calendar_connections(bookings)
    return unless current_user

    ids = bookings.filter_map do |booking|
      booking.program_id if booking.status == 'confirmed' && google_calendar_manager?(booking.program)
    end.uniq
    return if ids.empty?

    connections = GoogleCalendarConnection.where(:program_id.in => ids, enabled: true).index_by(&:program_id)
    google_calendar_connections.merge!(ids.index_with { |id| connections[id] })
  end

  def google_calendar_rsvp(program, booking)
    return unless booking.status == 'confirmed'

    responses = @google_calendar_responses ||= {}
    responses[program.id] ||= google_calendar_responses(program)
    responses[program.id][booking.id]
  end

  private

  def google_calendar_connections
    @google_calendar_connections ||= {}
  end

  def google_calendar_responses(program)
    return {} unless current_user && google_calendar_manager?(program)

    connection = google_calendar_connections.fetch(program.id) do
      GoogleCalendarConnection.where(program_id: program.id, enabled: true).first
    end
    return {} unless connection&.authorized?

    google_calendar_snapshots(program.id, connection.calendar_id)
  end

  def google_calendar_manager?(program)
    if respond_to?(:participant_dashboard)
      participant_dashboard.managed_program_ids.include?(program.id)
    else
      program.managed_by?(current_user)
    end
  end

  def google_calendar_snapshots(program_id, calendar_id)
    GoogleCalendarSync.where(program_id: program_id, rsvp_calendar_id: calendar_id,
                             :rsvp_status.in => GoogleCalendarRsvp::STATUSES)
                      .select do |sync|
      sync.rsvp_booking_id == sync.booking_id && sync.rsvp_fingerprint == sync.fingerprint
    end.index_by(&:booking_id)
  end
end
