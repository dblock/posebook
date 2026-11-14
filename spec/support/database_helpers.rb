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
    { name: 'Test Artist', gender: 'other', email: "artist-#{SecureRandom.hex(6)}@example.test",
      password: TEST_PASSWORD, password_confirmation: TEST_PASSWORD }.merge(overrides)
  end

  def create_user(**overrides)
    track_record(User.create!(user_attributes(**overrides)))
  end

  def create_drawing_session(**overrides)
    location = overrides.delete(:venue) || create_venue(**overrides.extract!(:address, :instagram_handle))
    track_record(DrawingSession.create!({ name: "Test Session #{SecureRandom.hex(4)}", venue: location }
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

  def grant_coordinator_access(drawing_session, user)
    DrawingSessionMembership.grant_coordinator_access(drawing_session, user)
    track_record(DrawingSessionMembership.find_by(drawing_session_id: drawing_session.id, user_id: user.id))
  end

  def create_model_invitation(drawing_session, inviter, **attributes)
    track_record(ModelInvitation.create!(drawing_session: drawing_session, invited_by: inviter, **attributes))
  end

  def track_model_membership(drawing_session, user)
    track_record(DrawingSessionMembership.find_by(drawing_session_id: drawing_session.id, user_id: user.id))
  end

  def grant_model_access(drawing_session, user)
    ModelInvitation.with_session do |session|
      DrawingSessionMembership.grant_model_access(drawing_session, user, session: session)
    end
    track_model_membership(drawing_session, user)
  end

  def track_booking(booking)
    track_record(booking)
    track_record(ModelBookingClaim.where(model_booking_id: booking.id).first)
    booking
  end

  def cleanup_records
    Mongoid::History.disable do
      tracked_records.reverse_each do |record|
        if record.is_a?(ModelBooking)
          ModelBooking.collection.find(_id: record.id).delete_one
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
