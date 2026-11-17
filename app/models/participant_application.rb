# frozen_string_literal: true

class ParticipantApplication
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :program, inverse_of: nil
  belongs_to :user, inverse_of: nil
  field :status, type: String, default: 'pending'
  field :message, type: String
  field :name, type: String
  field :email, type: String
  field :gender, type: String
  field :profile_shared_at, type: Time
  field :submitted_at, type: Time
  field :draft_profile, type: Hash, default: {}
  field :draft_reminded_at, type: Time
  field :draft_started_at, type: Time
  field :draft_origin, type: Hash, default: {}
  field :lock_version, type: Integer, default: 0

  index({ program_id: 1, user_id: 1 }, unique: true)
  index({ program_id: 1, status: 1, created_at: -1, _id: -1 })
  index({ program_id: 1, created_at: -1, _id: -1 })
  index({ user_id: 1, created_at: -1, _id: -1 })
  index({ status: 1, created_at: 1 })
  validates :status, inclusion: { in: %w[draft pending accepted declined withdrawn] }
  validates :message, length: { maximum: 5000 }
  validates :profile_shared_at, presence: true, unless: :draft?
  before_validation { self.message = message.to_s.strip.presence }

  def status_label
    status == 'declined' ? 'Reject' : status.titleize
  end

  def draft?
    status == 'draft'
  end

  def draft_revision
    "#{id}:#{lock_version}"
  end

  def draft_created_at
    draft_started_at || created_at
  end

  def discard_draft!(expired: false)
    record_event!(expired ? 'draft_expired' : 'draft_abandoned', actor: expired ? nil : user)
    return destroy! if draft_origin.empty?

    attributes = draft_origin.symbolize_keys.merge(status: 'withdrawn', draft_origin: {}, draft_profile: {},
                                                   draft_started_at: nil, draft_reminded_at: nil,
                                                   lock_version: lock_version + 1)
    update!(attributes)
  end

  def applicant_profile_attributes
    return draft_profile.slice(*ApplicationDraft::PROFILE_FIELDS) if draft?

    attributes.slice('name', 'email', 'gender').compact
  end

  def events
    ParticipationEvent.where(source_id: id).order_by(created_at: :asc, id: :asc)
  end

  def record_event!(action, actor:, notes: nil)
    ParticipationEvent.create!(program: program, user_id: user_id, actor: actor, source_id: id,
                               action: "application_#{action}", notes: notes)
  end
end
