# frozen_string_literal: true

class VenueSettingsUpdate
  def initialize(venue:, user:)
    @venue = venue
    @user = user
  end

  def call(attributes)
    Venue.with_session do |session|
      session.with_transaction do
        @venue.inc(booking_revision: 1)
        @venue.reload
        authorize!
        save_settings(attributes, session)
      end
    end
    @venue
  rescue Mongoid::Errors::Validations => e
    e.document
  end

  private

  def save_settings(attributes, session)
    @previous_location = @venue.attributes.slice('name', 'address')
    if attributes.key?(:notification_settings)
      settings = @venue.notification_settings.merge(attributes[:notification_settings])
      attributes = attributes.merge(notification_settings: settings)
    end
    @venue.update!(attributes)
    notify_bookings(session) if @venue.saved_change_to_address? || @venue.saved_change_to_name?
  end

  def authorize!
    raise LocationActivation::Forbidden unless @user.reload.active? && @venue.coordinated_by?(@user)
  end

  def notify_bookings(session)
    @venue.programs.order_by(id: :asc).each do |program|
      program.inc(schedule_revision: 1)
      program.venue = @venue
      records = Booking.upcoming.where(program_id: program.id)
      records.each do |booking|
        booking.program = program
        BookingNotification.record(booking, 'booking_changed', actor_id: @user.id,
                                                               key: "venue:#{@venue.version}:#{booking.lock_version}",
                                                               previous_location: @previous_location)
        GoogleCalendarSync.enqueue(booking, session: session)
      end
    end
  end
end
