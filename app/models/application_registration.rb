# frozen_string_literal: true

class ApplicationRegistration
  include Mongoid::Document
  include Mongoid::Timestamps
  include InvitationToken

  belongs_to :program, inverse_of: nil
  field :name, type: String
  field :email, type: String
  index({ expires_at: 1 }, expire_after_seconds: 0)
  before_validation :prepare_registration, on: :create, prepend: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }
  validate { errors.add(:base, 'This program is not accepting applications.') unless accepting? }

  def self.available(token)
    registration = super
    registration if registration&.accepting?
  end

  def accepting?
    target = Program.where(id: program_id).first
    target&.applications_enabled? && target.booking_active?
  end

  def grant_access(user, **)
    raise InvitationAcceptance::Unavailable unless accepting?

    user.update!(email_verified_at: Time.current)
  end

  private

  def prepare_registration
    self.email = email.to_s.strip.downcase
    self.expires_at ||= 30.minutes.from_now
  end
end
