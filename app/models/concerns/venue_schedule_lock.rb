# frozen_string_literal: true

module VenueScheduleLock
  private

  def with_schedule_lock
    Venue.with_session do |session|
      session.with_transaction do
        # Serialize bookings, exceptions, and settings; retry with fresh venue state.
        Venue.collection.find(_id: @venue.id).update_one({ '$inc' => { schedule_revision: 1 } }, session: session)
        @venue = Venue.find(@venue.id)
        yield session
      end
    end
  end
end
