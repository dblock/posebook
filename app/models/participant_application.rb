# frozen_string_literal: true

class ParticipantApplication
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :program, inverse_of: nil
  belongs_to :user, inverse_of: nil
  field :status, type: String, default: 'pending'
  field :message, type: String
  field :profile_shared_at, type: Time
  field :lock_version, type: Integer, default: 0

  index({ program_id: 1, user_id: 1 }, unique: true)
  index({ program_id: 1, status: 1, created_at: -1 })
  validates :status, inclusion: { in: %w[pending accepted declined withdrawn] }
  validates :message, length: { maximum: 5000 }
  validates :profile_shared_at, presence: true
  before_validation { self.message = message.to_s.strip.presence }

  def status_label
    status == 'declined' ? 'Not Now' : status.titleize
  end

  def events
    ParticipationEvent.where(source_id: id).order_by(created_at: :asc, id: :asc)
  end
end
