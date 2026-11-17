# frozen_string_literal: true

require 'digest'

class User
  include Mongoid::Document
  include Mongoid::Timestamps
  include ActiveModel::SecurePassword
  include PhoneSettings
  include AccountSettings
  include PublicProfile
  include HistoryTracking

  # MongoDB's built-in unique ID makes competing first-user registrations atomic.
  BOOTSTRAP_ID = BSON::ObjectId.from_string('000000000000000000000001')
  GLOBAL_ROLES = %w[system_admin].freeze
  GENDERS = %w[male female other].freeze

  field :name, type: String
  field :gender, type: String
  field :email, type: String
  field :password_digest, type: String
  field :roles, type: Array, default: []
  field :session_version, type: String, default: -> { SecureRandom.hex(16) }
  field :password_reset_digest, type: String
  field :password_reset_expires_at, type: Time
  field :booking_reminders_enabled, type: Mongoid::Boolean, default: true
  field :application_reminders_enabled, type: Mongoid::Boolean, default: true
  field :coordinator_notifications_enabled, type: Mongoid::Boolean, default: true

  track_history on: %i[name gender email phone roles active email_verified_at
                       display_name instagram_handle instagram_tagging_allowed booking_reminders_enabled
                       application_reminders_enabled coordinator_notifications_enabled],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true

  index({ email: 1 }, unique: true)
  index({ password_reset_digest: 1 })

  has_secure_password reset_token: false

  before_validation { self.email = email.to_s.strip.downcase }
  before_validation { self.gender = gender.presence }
  validates :gender, presence: true
  validates :gender, inclusion: { in: GENDERS }, allow_nil: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP },
                    length: { maximum: 254 }, uniqueness: true
  validates :password, length: { minimum: 12 }, allow_nil: true
  validate { errors.add(:roles, :invalid) unless (roles - GLOBAL_ROLES).empty? }

  def self.bootstrap(attributes)
    user = new(attributes)
    user.assign_attributes(id: BOOTSTRAP_ID, roles: ['system_admin'])
    if exists?
      user.errors.add(:base, 'Registration is closed.')
    else
      user.save
    end
    user
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000

    user.errors.add(:base, 'Registration is closed.')
    user
  end

  def self.for_password_reset(token)
    return if token.blank?

    active.where(password_reset_digest: Digest::SHA256.hexdigest(token),
                 :password_reset_expires_at.gt => Time.current).first
  end

  def system_admin?
    roles.include?('system_admin')
  end

  def booking_reminder_token
    Rails.application.message_verifier('booking-reminders').generate(id.to_s, purpose: 'preferences')
  end

  def self.for_booking_reminder_token(token)
    id = Rails.application.message_verifier('booking-reminders').verified(token.to_s, purpose: 'preferences')
    active.where(id: id).first if id
  end

  def update_by_admin(attributes)
    assign_attributes(attributes.slice(:name, :email, :phone, :gender, *PublicProfile::FIELDS))
    self.email = email.to_s.strip.downcase
    clear_email_authentication if email_changed?
    save
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000

    errors.add(:email, :taken)
    false
  end

  def self.with_email(email)
    active.where(email: email.to_s.strip.downcase).first
  end

  def send_password_reset
    token = SecureRandom.urlsafe_base64(32)
    expires_at = 30.minutes.from_now
    EmailDelivery.enqueue('password_reset', self, token: token, expires_at: expires_at) do
      reload
      active? && set(password_reset_digest: Digest::SHA256.hexdigest(token), password_reset_expires_at: expires_at)
    end
  end

  def reset_password(token, attributes)
    assign_attributes(attributes)
    return false unless valid?

    result = self.class.collection.find(
      _id: id, active: { '$ne' => false }, password_reset_digest: Digest::SHA256.hexdigest(token),
      password_reset_expires_at: { '$gt' => Time.current }
    ).find_one_and_update(
      '$set' => { password_digest: password_digest, session_version: SecureRandom.hex(16), updated_at: Time.current },
      '$unset' => authentication_challenges
    )
    errors.add(:base, 'This reset link is invalid or expired.') unless result
    result
  end
end
