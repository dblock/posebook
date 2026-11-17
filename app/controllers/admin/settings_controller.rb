# frozen_string_literal: true

module Admin
  class SettingsController < ApplicationController
    before_action :require_authentication
    before_action :require_system_admin

    def show
      redirect_to admin_settings_notifications_path
    end
  end
end
