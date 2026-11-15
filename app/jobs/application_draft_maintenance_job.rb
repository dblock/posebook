# frozen_string_literal: true

class ApplicationDraftMaintenanceJob < ApplicationJob
  queue_as :maintenance

  def perform
    ApplicationDraftMaintenance.run
  end
end
