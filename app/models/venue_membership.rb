# frozen_string_literal: true

class VenueMembership
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :venue, inverse_of: :memberships
  belongs_to :user, inverse_of: nil
  field :roles, type: Array, default: []

  index({ venue_id: 1, user_id: 1 }, unique: true)
  index({ user_id: 1, roles: 1 })
  scope :schedule_managers, -> { where(:roles.in => ['manage_schedule']) }
  validate { errors.add(:roles, :invalid) unless (roles - ['manage_schedule']).empty? }

  def self.grant_schedule_access(venue, user)
    collection.find(venue_id: venue.id, user_id: user.id).update_one(
      { '$setOnInsert' => { _id: BSON::ObjectId.new, created_at: Time.current },
        '$set' => { updated_at: Time.current },
        '$addToSet' => { roles: 'manage_schedule' } },
      upsert: true
    )
  end

  def revoke_schedule_access
    pull(roles: 'manage_schedule')
  end
end
