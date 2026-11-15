# frozen_string_literal: true

module ProgramScheduleLock
  private

  def with_schedule_lock
    Program.with_session do |session|
      session.with_transaction do
        # Venue activation and every program mutation share this write barrier.
        Venue.collection.find(_id: @program.venue_id).update_one({ '$inc' => { booking_revision: 1 } },
                                                                 session: session)
        # Serialize bookings, exceptions, and settings; retry with fresh program state.
        Program.collection.find(_id: @program.id).update_one({ '$inc' => { schedule_revision: 1 } },
                                                             session: session)
        @program = Program.find(@program.id)
        yield session
      end
    end
  end
end
