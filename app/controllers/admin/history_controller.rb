# frozen_string_literal: true

module Admin
  class HistoryController < ApplicationController
    before_action :require_authentication
    before_action :require_system_admin
    before_action -> { response.headers['Cache-Control'] = 'private, no-store' }

    def index
      @history = AuditHistory.new(cursor: params[:cursor])
      @entries = @history.entries
    end
  end
end
