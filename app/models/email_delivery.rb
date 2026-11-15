# frozen_string_literal: true

class EmailDelivery
  include Mongoid::Document
  include Mongoid::Timestamps

  class Unavailable < StandardError; end
  class Failed < StandardError; end

  KINDS = %w[password_reset email_change participant_invitation coordinator_invitation booking_invitation
             application_registration participation_event participation_admission].freeze

  field :kind, type: String
  field :resource_id, type: BSON::ObjectId
  field :recipient_id, type: BSON::ObjectId
  field :queued_job_id, type: BSON::ObjectId
  field :encrypted_token, type: String
  field :expires_at, type: Time
  field :grant_invited_at, type: Time
  index({ expires_at: 1 }, expire_after_seconds: 0)
  index({ resource_id: 1 })
  validates :kind, inclusion: { in: KINDS }
  validates :resource_id, presence: true
  validates :encrypted_token, :expires_at,
            presence: true, unless: lambda {
              %w[booking_invitation participation_event participation_admission].include?(kind)
            }
  validates :grant_invited_at, presence: true, if: -> { kind == 'booking_invitation' }
  validates :recipient_id, presence: true, if: -> { %w[participation_event participation_admission].include?(kind) }

  def self.enqueue(kind, resource, token: nil, expires_at: nil, grant_invited_at: nil)
    result = false
    with_session do |session|
      session.with_transaction do
        result = false
        next if block_given? && !yield

        result = enqueue_in_transaction(kind, resource, session: session, token: token, expires_at: expires_at,
                                                        grant_invited_at: grant_invited_at)
      end
    end
    result
  rescue Mongo::Error, ActiveJob::EnqueueError => e
    raise Unavailable, e.class.name, cause: nil
  end

  def self.enqueue_in_transaction(kind, resource, session:, **attributes)
    raise Unavailable, 'Email enqueue requires an active transaction' unless session.in_transaction?

    token = attributes.delete(:token)
    result = new(kind: kind, resource_id: resource.id, **attributes)
    result.token = token if token
    result.save!
    job = EmailDeliveryJob.perform_later(result.id.to_s).presence
    raise Unavailable, 'Email enqueue failed' unless job&.successfully_enqueued?

    result.update!(queued_job_id: job.provider_job_id)
    result
  rescue ActiveJob::EnqueueError => e
    raise Unavailable, e.class.name, cause: nil
  end

  def token=(value)
    self.encrypted_token = encryptor.encrypt_and_sign(value)
  end

  def token
    encryptor.decrypt_and_verify(encrypted_token) if encrypted_token
  end

  def deliver
    message = EmailDeliveryMessage.new(self).build unless expires_at && expires_at <= Time.current
    if message
      unless Rails.configuration.x.password_reset_delivery_enabled && ActionMailer::Base.perform_deliveries
        raise Unavailable, 'Email delivery is not configured'
      end

      message.message.raise_delivery_errors = true
      message.deliver_now
    end
    destroy!
  end

  private

  def encryptor
    key = Rails.application.key_generator.generate_key('email-delivery-token', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
end
