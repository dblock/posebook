# frozen_string_literal: true

class GoogleCalendarReconcileJob < ApplicationJob
  queue_as :calendar

  def perform
    GoogleCalendarSync.reconcile
  end
end
