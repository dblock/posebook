# frozen_string_literal: true

class BookingNotificationMaintenanceJob < ApplicationJob
  queue_as :maintenance

  def perform
    BookingNotificationMaintenance.run
  end
end
