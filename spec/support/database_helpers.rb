# frozen_string_literal: true

module DatabaseHelpers
  TEST_PASSWORD = 'a sufficiently long test password'

  def tracked_records
    @tracked_records ||= []
  end

  def track_record(record)
    tracked_records << record if record
    record
  end

  def user_attributes(**overrides)
    { name: 'Test Participant', phone: '+12025550101', gender: 'other',
      email: "participant-#{SecureRandom.hex(6)}@example.test",
      password: TEST_PASSWORD, password_confirmation: TEST_PASSWORD }.merge(overrides)
  end

  def create_user(**overrides)
    track_record(User.create!(user_attributes(**overrides)))
  end

  def create_program(**overrides)
    location = overrides.delete(:venue) || create_venue(**overrides.extract!(:address, :instagram_handle))
    track_record(Program.create!({ name: "Test Program #{SecureRandom.hex(4)}", venue: location }
                               .merge(overrides)))
  end

  def create_venue(**overrides)
    track_record(Venue.create!({ name: "Test Venue #{SecureRandom.hex(4)}", address: '480 10th Avenue, New York' }
                              .merge(overrides)))
  end

  def grant_venue_access(venue, user)
    VenueMembership.grant_coordinator_access(venue, user)
    track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
  end

  def grant_coordinator_access(program, user)
    ProgramMembership.grant_coordinator_access(program, user)
    track_record(ProgramMembership.find_by(program_id: program.id, user_id: user.id))
  end

  def create_participant_invitation(program, inviter, **attributes)
    track_record(ParticipantInvitation.create!(program: program, invited_by: inviter, **attributes))
  end

  def create_coordinator_invitation(target, inviter, **attributes)
    scope = target.is_a?(Venue) ? { venue: target } : { program: target }
    attributes = { email: user_attributes[:email] }.merge(attributes)
    track_record(CoordinatorInvitation.create!(**scope, invited_by: inviter, **attributes))
  end

  def track_participant_membership(program, user)
    track_record(ProgramMembership.find_by(program_id: program.id, user_id: user.id))
  end

  def grant_participant_access(program, user)
    ParticipantInvitation.with_session do |session|
      ProgramMembership.grant_participant_access(program, user, session: session)
    end
    track_participant_membership(program, user)
  end

  def track_booking(booking)
    track_record(booking)
    track_record(BookingClaim.where(booking_id: booking.id).first)
    booking
  end

  def cleanup_records
    Mongoid::History.disable do
      tracked_records.reverse_each do |record|
        if record.is_a?(Booking)
          Booking.collection.find(_id: record.id).delete_one
        elsif record.persisted?
          record.destroy
        end
      end
    end
    HistoryTracker.where(:'association_chain.id'.in => tracked_records.map(&:id)).delete_all
  end

  def sign_in(user, client: self)
    client.post(session_path, params: { email: user.email, password: TEST_PASSWORD })
  end

  def reset_token(user)
    user.send_password_reset
    ActionMailer::Base.deliveries.last.body.decoded[%r{/password_resets/([^/]+)/edit}, 1]
  end
end
