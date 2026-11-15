# frozen_string_literal: true

module GoogleCalendarHelper
  def google_calendar_rsvp(program, booking)
    return unless booking.status == 'confirmed'

    responses = request.env['posebook.google_calendar_responses'] ||= {}
    responses[program.id] ||= google_calendar_responses(program)
    responses[program.id][booking.id]
  end

  private

  def google_calendar_responses(program)
    return {} unless current_user && google_calendar_manager?(program)

    connection = GoogleCalendarConnection.where(program_id: program.id, enabled: true).first
    return {} unless connection&.authorized?

    google_calendar_snapshots(program.id, connection.calendar_id)
  end

  def google_calendar_manager?(program)
    dashboard = request.env['posebook.dashboard']
    dashboard ? dashboard.managed_program_ids.include?(program.id) : program.managed_by?(current_user)
  end

  def google_calendar_snapshots(program_id, calendar_id)
    GoogleCalendarSync.where(program_id: program_id, rsvp_calendar_id: calendar_id,
                             :rsvp_status.in => GoogleCalendarRsvp::STATUSES)
                      .select do |sync|
      sync.rsvp_booking_id == sync.booking_id && sync.rsvp_fingerprint == sync.fingerprint
    end.index_by(&:booking_id)
  end
end
