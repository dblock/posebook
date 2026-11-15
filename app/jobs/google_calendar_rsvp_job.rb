# frozen_string_literal: true

class GoogleCalendarRsvpJob < ApplicationJob
  queue_as :calendar

  def perform(sync_id)
    sync = GoogleCalendarSync.where(id: sync_id).first
    GoogleCalendarRsvp.new(sync).refresh if sync
  end
end
