# frozen_string_literal: true

class GoogleCalendarRsvpPollJob < ApplicationJob
  queue_as :calendar

  def perform
    GoogleCalendarRsvp.enqueue_checks
  end
end
