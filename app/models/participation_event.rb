# frozen_string_literal: true

class ParticipationEvent
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  REVIEW_ACTIONS = %w[application_submitted application_accepted application_declined application_withdrawn
                      invitation_accepted].freeze
  ACTIONS = (REVIEW_ACTIONS + %w[application_draft_created application_reopened application_draft_abandoned
                                 application_draft_expired]).freeze

  belongs_to :program, inverse_of: nil
  belongs_to :user, inverse_of: nil
  belongs_to :actor, class_name: 'User', inverse_of: nil, optional: true
  field :action, type: String
  field :source_id, type: BSON::ObjectId
  field :notes, type: String
  index({ program_id: 1, created_at: -1, _id: -1 })
  index({ source_id: 1, created_at: 1 })
  validates :action, inclusion: { in: ACTIONS }
  validates :source_id, presence: true
  validates :actor, presence: true, unless: -> { action == 'application_draft_expired' }
  validates :notes, length: { maximum: 200 }
  before_validation { self.notes = notes.to_s.strip.presence }

  scope :reviewable, -> { where(:action.in => REVIEW_ACTIONS) }

  def label
    action == 'application_declined' ? 'Application Rejected' : action.humanize
  end
end
