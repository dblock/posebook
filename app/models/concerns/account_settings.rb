# frozen_string_literal: true

module AccountSettings
  extend ActiveSupport::Concern

  included do
    attr_accessor :current_password

    field :phone, type: String
    field :active, type: Mongoid::Boolean, default: true
    field :pending_email, type: String
    field :email_verified_at, type: Time
    field :email_change_digest, type: String
    field :email_change_expires_at, type: Time
    index({ email_change_digest: 1 })
    scope :active, -> { where(:active.ne => false) }
    before_validation { self.phone = phone.to_s.strip.presence }
    validates :phone, format: { with: /\A\+[1-9]\d{7,14}\z/ }, allow_blank: true
    validates :pending_email, format: { with: URI::MailTo::EMAIL_REGEXP },
                              length: { maximum: 254 }, allow_nil: true
  end

  def password_matches?(password)
    return true if authenticate(password.to_s)

    errors.add(:current_password, :invalid)
    false
  end

  def update_profile(attributes)
    assign_attributes(attributes.slice(:name, :phone, :gender, *PublicProfile::FIELDS))
    new_email = attributes[:email].to_s.strip.downcase
    return save if new_email == email
    return false unless password_matches?(attributes[:current_password])

    self.pending_email = new_email
    return false unless valid? && email_available?

    send_email_change
  end

  def send_email_change
    unless Rails.configuration.x.password_reset_delivery_enabled
      errors.add(:base, I18n.t('password_resets.unavailable'))
      return false
    end
    token = SecureRandom.urlsafe_base64(32)
    self.email_change_digest = Digest::SHA256.hexdigest(token)
    self.email_change_expires_at = 30.minutes.from_now
    return false unless save

    EmailChangeMailer.confirm(self, token).deliver_now
  end

  def confirm_email_change(token)
    result = save_tracked_change(authentication_updates.merge(email: pending_email, email_verified_at: Time.current)) do
      email_change_claim(token)
    end
    errors.add(:base, I18n.t('email_changes.invalid')) unless result
    result
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000

    errors.add(:pending_email, :taken)
    false
  end

  def change_password(attributes)
    return false unless password_matches?(attributes.delete(:current_password))

    assign_attributes(attributes)
    return false unless valid?

    self.class.collection.find(_id: id, session_version: session_version, active: { '$ne' => false })
        .find_one_and_update(
          '$set' => { password_digest: password_digest, session_version: SecureRandom.hex(16),
                      updated_at: Time.current },
          '$unset' => authentication_challenges
        )
  end

  def deactivate
    if system_admin?
      errors.add(:base, I18n.t('accounts.admin_protected'))
      return false
    end
    save_tracked_change(authentication_updates.merge(active: false)) do
      self.class.where(_id: id, :roles.ne => 'system_admin')
    end
  end

  def reactivate
    save_tracked_change(active: true, session_version: SecureRandom.hex(16)) { self.class.where(_id: id) }
  end

  private

  def authentication_updates
    authentication_challenges.transform_values { nil }.merge(session_version: SecureRandom.hex(16))
  end

  def clear_email_authentication
    assign_attributes(authentication_updates.merge(email_verified_at: nil))
  end

  def email_available?
    return true unless self.class.exists?(email: pending_email)

    errors.add(:pending_email, :taken)
    false
  end

  def authentication_challenges
    %w[password_reset_digest password_reset_expires_at pending_email email_change_digest email_change_expires_at]
      .index_with { '' }
  end

  def email_change_claim(token)
    self.class.where(
      _id: id, active: { '$ne' => false }, email_change_digest: Digest::SHA256.hexdigest(token),
      email_change_expires_at: { '$gt' => Time.current }
    )
  end
end
