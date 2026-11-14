# frozen_string_literal: true

class VenueSettingsUpdate
  include VenueScheduleLock

  def initialize(venue:, user:)
    @venue = venue
    @user = user
  end

  def call(attributes)
    with_schedule_lock do |session|
      previous_time = @venue.start_time
      @venue.update!(attributes)
      update_booking_times(session) if previous_time != @venue.start_time
    end
    @venue
  rescue Mongoid::Errors::Validations => e
    e.document
  rescue ArgumentError => e
    @venue.errors.add(:start_time, e.message)
    @venue
  end

  private

  def update_booking_times(session)
    schedule = VenueSchedule.new(@venue)
    records = ModelBooking.upcoming.where(venue_id: @venue.id)
    records.each do |booking|
      next if schedule.exceptions[booking.date]&.mode.in?(%w[open closed])

      start = VenueSchedule.local_start(booking.date, @venue.start_time, booking.time_zone)
      booking.change_time!(start, 'Regular drawing time changed.', @user, session: session)
    end
  end
end
