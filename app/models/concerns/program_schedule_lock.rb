# frozen_string_literal: true

module ProgramScheduleLock
  private

  def with_schedule_lock
    Program.with_session do |session|
      session.with_transaction do
        # Serialize bookings, exceptions, and settings; retry with fresh program state.
        Program.collection.find(_id: @program.id).update_one({ '$inc' => { schedule_revision: 1 } },
                                                             session: session)
        @program = Program.find(@program.id)
        yield session
      end
    end
  end
end
