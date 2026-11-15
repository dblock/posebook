# frozen_string_literal: true

class GoogleCalendarRsvp
  STATUSES = %w[needsAction accepted tentative declined].freeze

  def self.enqueue_checks
    programs = GoogleCalendarConnection.where(enabled: true).distinct(:program_id)
    bookings = Booking.upcoming.where(:program_id.in => programs).pluck(:id)
    syncs = GoogleCalendarSync.where(:booking_id.in => bookings, :fingerprint.ne => nil)
    syncs.each do |sync|
      GoogleCalendarRsvpJob.perform_later(sync.id.to_s)
    end
  end

  def initialize(sync)
    @sync = sync
    @snapshot = { _id: sync.id, revision: sync.revision, booking_id: sync.booking_id,
                  fingerprint: sync.fingerprint, rsvp_checked_at: sync.rsvp_checked_at }
  end

  def refresh
    connection = connection_for(@sync)
    return unless eligible?(@sync, connection)

    status = response_status(connection)
    current = GoogleCalendarSync.where(@snapshot).first
    return unless current && eligible?(current, connection_for(current))

    GoogleCalendarSync.collection.find(@snapshot).update_one(
      '$set' => { rsvp_status: status, rsvp_checked_at: Time.current, rsvp_booking_id: current.booking_id,
                  rsvp_calendar_id: connection.calendar_id, rsvp_fingerprint: current.fingerprint }
    )
  end

  private

  def connection_for(sync)
    GoogleCalendarConnection.where(program_id: sync.program_id, enabled: true).first
  end

  def eligible?(sync, connection)
    return false unless connection&.authorized? && sync.fingerprint.present?
    return false unless sync.booking.status == 'confirmed' && sync.booking.ends_at > Time.current
    return false if fresh?(sync, connection)

    sync.fingerprint == sync.payload_fingerprint(connection)
  end

  def fresh?(sync, connection)
    sync.rsvp_checked_at && sync.rsvp_checked_at > 12.hours.ago &&
      sync.rsvp_fingerprint == sync.fingerprint && sync.rsvp_booking_id == sync.booking_id &&
      sync.rsvp_calendar_id == connection.calendar_id
  end

  def response_status(connection)
    event = connection.service.get_event(connection.calendar_id, @sync.event_id)
    return if event&.status == 'cancelled'

    attendee_status(event)
  rescue Google::Apis::ClientError => e
    raise unless [404, 410].include?(e.status_code)
  end

  def attendee_status(event)
    guests = event&.attendees || []
    email = @sync.booking.user.email
    status = guests.find { |guest| guest.email.to_s.casecmp?(email) }&.response_status
    status if STATUSES.include?(status)
  end
end
