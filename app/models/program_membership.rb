# frozen_string_literal: true

class ProgramMembership
  include Mongoid::Document
  include Mongoid::Timestamps
  include HistoryTracking

  belongs_to :program, inverse_of: :memberships
  belongs_to :user, inverse_of: nil
  field :roles, type: Array, default: []
  field :booking_invited_at, type: Time
  field :booking_invited_by_id, type: BSON::ObjectId
  field :participant_paused, type: Mongoid::Boolean, default: false
  field :participant_pause_reason, type: String
  field :notes, type: String
  field :display_name_override, type: String
  field :instagram_hidden, type: Mongoid::Boolean, default: false
  field :photos_hidden, type: Mongoid::Boolean, default: false
  before_validation do
    self.notes = notes.to_s.strip.presence
    self.display_name_override = display_name_override.to_s.strip.presence
  end

  track_history on: %i[booking_invited_at booking_invited_by_id participant_paused participant_pause_reason notes
                       display_name_override instagram_hidden photos_hidden],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true
  validates :participant_pause_reason, presence: true, length: { maximum: 200 }, if: :participant_paused?
  validates :display_name_override, length: { maximum: 100 }, allow_nil: true

  index({ program_id: 1, user_id: 1 }, unique: true)
  index({ user_id: 1, roles: 1 })
  scope :coordinators, -> { where(:roles.in => ['program_coordinator']) }
  scope :participants, -> { where(:roles.in => ['participant']) }
  validate { errors.add(:roles, :invalid) unless (roles - %w[program_coordinator participant]).empty? }

  def self.grant_coordinator_access(program, user, session: nil)
    grant_role(program, user, 'program_coordinator', session: session)
  end

  def self.grant_participant_access(program, user, session:)
    existing = where(program_id: program.id, user_id: user.id).first
    grant_role(program, user, 'participant', session: session)
    return if existing&.roles&.include?('participant')

    where(program_id: program.id, user_id: user.id).first.update!(booking_invited_at: Time.current)
  end

  def self.grant_role(program, user, role, session: nil)
    collection.find(program_id: program.id, user_id: user.id).update_one(
      { '$setOnInsert' => { _id: BSON::ObjectId.new, created_at: Time.current },
        '$set' => { updated_at: Time.current },
        '$addToSet' => { roles: role } },
      upsert: true, session: session
    )
  end
  private_class_method :grant_role

  def participant_display_name
    display_name_override || user.display_name
  end

  def participant_public_name
    user.active? && participant_display_name.present? ? participant_display_name : 'To be announced'
  end

  def participant_instagram_handle
    user.public_instagram_handle unless instagram_hidden?
  end

  def revoke_coordinator_access
    pull(roles: 'program_coordinator')
  end
end
