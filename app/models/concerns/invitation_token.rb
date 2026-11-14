# frozen_string_literal: true

module InvitationToken
  extend ActiveSupport::Concern

  included do
    attr_accessor :token

    field :token_digest, type: String
    field :expires_at, type: Time
    field :used_at, type: Time
    field :used_by_id, type: BSON::ObjectId
    field :revoked_at, type: Time

    index({ token_digest: 1 }, unique: true)
    before_validation :prepare_token, on: :create
  end

  class_methods do
    def available(token)
      return unless token.to_s.match?(/\A[A-Za-z0-9_-]{43}\z/)

      where(token_digest: Digest::SHA256.hexdigest(token), used_at: nil, revoked_at: nil,
            :expires_at.gt => Time.current).first
    end
  end

  def revoke
    self.class.collection.find(_id: id, used_at: nil, revoked_at: nil).find_one_and_update(
      '$set' => { revoked_at: Time.current, updated_at: Time.current }
    )
  end

  def status
    return 'Accepted' if used_at
    return 'Revoked' if revoked_at
    return 'Expired' if expires_at <= Time.current

    'Pending'
  end

  private

  def prepare_token
    self.token ||= SecureRandom.urlsafe_base64(32)
    self.token_digest = Digest::SHA256.hexdigest(token)
    self.expires_at ||= 30.days.from_now
  end
end
