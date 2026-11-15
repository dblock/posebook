# frozen_string_literal: true

class ParticipantInvitation
  include Mongoid::Document
  include Mongoid::Timestamps
  include InvitationToken

  belongs_to :program, inverse_of: :participant_invitations
  belongs_to :invited_by, class_name: 'User', inverse_of: nil
  field :name, type: String
  field :email, type: String
  index({ program_id: 1, created_at: -1 })
  validates :name, length: { maximum: 100 }, allow_nil: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }, allow_nil: true
  before_validation { self.email = email.to_s.strip.downcase.presence }

  def grant_access(user, session:)
    ProgramMembership.grant_participant_access(program, user, session: session)
    event = ParticipationEvent.create!(program: program, user: user, actor: invited_by,
                                       action: 'invitation_accepted', source_id: id)
    ParticipationNotification.new(event).enqueue(session: session)
  end
end
