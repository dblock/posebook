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

  def create_venue(**overrides)
    track_record(Venue.create!({ name: "Test Venue #{SecureRandom.hex(4)}", address: '480 10th Avenue, New York' }
                               .merge(overrides)))
  end

  def grant_schedule_access(venue, user)
    VenueMembership.grant_schedule_access(venue, user)
    track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
  end

  def create_model_invitation(venue, inviter, **attributes)
    track_record(ModelInvitation.create!(venue: venue, invited_by: inviter, **attributes))
  end

  def track_model_membership(venue, user)
    track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
  end

  def grant_model_access(venue, user)
    ModelInvitation.with_session { |session| VenueMembership.grant_model_access(venue, user, session: session) }
    track_model_membership(venue, user)
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
