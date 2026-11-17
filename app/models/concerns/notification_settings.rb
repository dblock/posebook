# frozen_string_literal: true

module NotificationSettings
  extend ActiveSupport::Concern

  included do
    field :notification_settings, type: Hash, default: {}
    validate :validate_notification_settings
  end

  private

  def validate_notification_settings
    notification_settings.each_key do |kind|
      unless NotificationCatalog.kinds_for(self).include?(kind)
        errors.add(:notification_settings, 'contains an unknown notification')
        next
      end
      setting = NotificationSetting.for(self, kind)
      setting.errors.full_messages.each { |message| errors.add(:notification_settings, message) } unless setting.valid?
    end
  end
end
