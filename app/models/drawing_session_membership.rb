# frozen_string_literal: true

class DrawingSessionMembership
  include Mongoid::Document
  include Mongoid::Timestamps
  include HistoryTracking

  belongs_to :drawing_session, inverse_of: :memberships
  belongs_to :user, inverse_of: nil
  field :roles, type: Array, default: []
  field :booking_invited_at, type: Time
  field :booking_invited_by_id, type: BSON::ObjectId
  field :model_paused, type: Mongoid::Boolean, default: false
  field :model_pause_reason, type: String

  track_history on: %i[booking_invited_at booking_invited_by_id model_paused model_pause_reason],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true
  validates :model_pause_reason, presence: true, length: { maximum: 200 }, if: :model_paused?

  index({ drawing_session_id: 1, user_id: 1 }, unique: true)
  index({ user_id: 1, roles: 1 })
  scope :coordinators, -> { where(:roles.in => ['session_coordinator']) }
  scope :models, -> { where(:roles.in => ['model']) }
  validate { errors.add(:roles, :invalid) unless (roles - %w[session_coordinator model]).empty? }

  def self.grant_coordinator_access(drawing_session, user)
    grant_role(drawing_session, user, 'session_coordinator')
  end

  def self.grant_model_access(drawing_session, user, session:)
    existing = where(drawing_session_id: drawing_session.id, user_id: user.id).first
    grant_role(drawing_session, user, 'model', session: session)
    return if existing&.roles&.include?('model')

    where(drawing_session_id: drawing_session.id, user_id: user.id).first.update!(booking_invited_at: Time.current)
  end

  def self.grant_role(drawing_session, user, role, session: nil)
    collection.find(drawing_session_id: drawing_session.id, user_id: user.id).update_one(
      { '$setOnInsert' => { _id: BSON::ObjectId.new, created_at: Time.current },
        '$set' => { updated_at: Time.current },
        '$addToSet' => { roles: role } },
      upsert: true, session: session
    )
  end
  private_class_method :grant_role

  def revoke_coordinator_access
    pull(roles: 'session_coordinator')
  end
end
