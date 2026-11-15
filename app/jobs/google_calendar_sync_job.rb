# frozen_string_literal: true

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :calendar

  def perform
    100.times { break unless GoogleCalendarSync.process_next }
  end
end
