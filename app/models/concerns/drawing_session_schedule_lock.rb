# frozen_string_literal: true

module DrawingSessionScheduleLock
  private

  def with_schedule_lock
    DrawingSession.with_session do |session|
      session.with_transaction do
        # Serialize bookings, exceptions, and settings; retry with fresh drawing_session state.
        DrawingSession.collection.find(_id: @drawing_session.id).update_one({ '$inc' => { schedule_revision: 1 } },
                                                                            session: session)
        @drawing_session = DrawingSession.find(@drawing_session.id)
        yield session
      end
    end
  end
end
