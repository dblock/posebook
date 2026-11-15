# frozen_string_literal: true

class GoogleCalendarConnection
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :program, inverse_of: nil
  belongs_to :connected_by, class_name: 'User', inverse_of: nil
  field :calendar_id, type: String
  field :encrypted_refresh_token, type: String
  field :enabled, type: Mongoid::Boolean, default: true
  index({ program_id: 1 }, unique: true)
  validates :calendar_id, presence: true
  validates :encrypted_refresh_token, presence: true, if: :enabled?
  validates :calendar_id, length: { maximum: 254 }

  SCOPES = %w[https://www.googleapis.com/auth/calendar.events
              https://www.googleapis.com/auth/calendar.calendarlist.readonly].freeze

  def self.configured?
    %w[GOOGLE_CALENDAR_CLIENT_ID GOOGLE_CALENDAR_CLIENT_SECRET GOOGLE_CALENDAR_REDIRECT_URI]
      .all? { |name| ENV[name].present? }
  end

  def self.credentials
    Google::Auth::UserRefreshCredentials.new(
      client_id: ENV.fetch('GOOGLE_CALENDAR_CLIENT_ID'),
      client_secret: ENV.fetch('GOOGLE_CALENDAR_CLIENT_SECRET'),
      redirect_uri: ENV.fetch('GOOGLE_CALENDAR_REDIRECT_URI'), scope: SCOPES
    )
  end

  def refresh_token=(token)
    self.encrypted_refresh_token = encryptor.encrypt_and_sign(token)
  end

  def service
    auth = self.class.credentials
    auth.refresh_token = encryptor.decrypt_and_verify(encrypted_refresh_token)
    self.class.service(auth)
  end

  def authorized?
    connected_by.active? && program.managed_by?(connected_by)
  end

  def self.service(auth)
    Google::Apis::CalendarV3::CalendarService.new.tap do |client|
      client.authorization = auth
      client.client_options.open_timeout_sec = 10
      client.client_options.read_timeout_sec = 30
      client.request_options.retries = 0
    end
  end

  private

  def encryptor
    key = Rails.application.key_generator.generate_key('google-calendar-refresh-token', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
end
