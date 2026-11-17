# frozen_string_literal: true

class NotificationDefaults
  include Mongoid::Document
  include Mongoid::Timestamps
  include HistoryTracking
  include NotificationSettings

  ID = BSON::ObjectId.from_string('000000000000000000000002')
  field :revision, type: Integer, default: 0
  track_history on: [:notification_settings], modifier_field_optional: true,
                modifier_field_inverse_of: nil, track_blank_changes: true

  def self.current
    where(id: ID).first || new(id: ID)
  end

  def name = 'Notification Defaults'
end
