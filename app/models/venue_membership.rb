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
  scope :models, -> { where(:roles.in => ['model']) }
  validate { errors.add(:roles, :invalid) unless (roles - %w[manage_schedule model]).empty? }

  def self.grant_schedule_access(venue, user)
    grant_role(venue, user, 'manage_schedule')
  end

  def self.grant_model_access(venue, user, session:)
    grant_role(venue, user, 'model', session: session)
  end

  def self.grant_role(venue, user, role, session: nil)
    collection.find(venue_id: venue.id, user_id: user.id).update_one(
      { '$setOnInsert' => { _id: BSON::ObjectId.new, created_at: Time.current },
        '$set' => { updated_at: Time.current },
        '$addToSet' => { roles: role } },
      upsert: true, session: session
    )
  end
  private_class_method :grant_role

  def revoke_schedule_access
    pull(roles: 'manage_schedule')
  end
end
