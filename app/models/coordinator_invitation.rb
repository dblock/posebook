# frozen_string_literal: true

class CoordinatorInvitation
  include Mongoid::Document
  include Mongoid::Timestamps
  include InvitationToken

  belongs_to :venue, inverse_of: nil, optional: true
  belongs_to :program, inverse_of: nil, optional: true
  belongs_to :invited_by, class_name: 'User', inverse_of: nil
  field :name, type: String
  field :email, type: String

  index({ venue_id: 1, program_id: 1, created_at: -1 })
  validates :name, length: { maximum: 100 }, allow_nil: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }, allow_nil: true
  validate { errors.add(:base, :invalid) unless venue.present? ^ program.present? }
  before_validation { self.email = email.to_s.strip.downcase.presence }

  def self.available(token)
    invitation = super
    invitation if invitation&.authorized?
  end

  def target
    venue || program
  end

  def coordinator_label
    "#{program ? program.program_label.titleize : 'Venue'} Coordinator"
  end

  def authorized?
    invited_by.active? && (venue ? invited_by.system_admin? : program.venue.coordinated_by?(invited_by))
  end

  def acceptable_by?(user)
    super && authorized?
  end

  def grant_access(user, session: nil)
    if venue
      VenueMembership.grant_coordinator_access(venue, user, session: session)
    else
      ProgramMembership.grant_coordinator_access(program, user, session: session)
    end
  end
end
