# frozen_string_literal: true

module Admin
  class NotificationsController < NotificationSettingsController
    private

    def find_scope
      require_system_admin
      response.headers['Cache-Control'] = 'private, no-store'
      @notification_scope = NotificationDefaults.current unless performed?
    end
  end
end
