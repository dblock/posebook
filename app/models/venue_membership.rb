# frozen_string_literal: true

class VenueMembership
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :venue, inverse_of: :memberships
  belongs_to :user, inverse_of: nil
  field :roles, type: Array, default: []

  index({ venue_id: 1, user_id: 1 }, unique: true)
  index({ user_id: 1, roles: 1 })
  scope :coordinators, -> { where(:roles.in => ['venue_coordinator']) }
  validate { errors.add(:roles, :invalid) unless (roles - ['venue_coordinator']).empty? }

  def self.grant_coordinator_access(venue, user, session: nil)
    collection.find(venue_id: venue.id, user_id: user.id).update_one(
      { '$setOnInsert' => { _id: BSON::ObjectId.new, created_at: Time.current },
        '$set' => { updated_at: Time.current },
        '$addToSet' => { roles: 'venue_coordinator' } }, upsert: true, session: session
    )
  end

  def revoke_coordinator_access
    pull(roles: 'venue_coordinator')
  end
end
