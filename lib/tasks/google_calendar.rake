# frozen_string_literal: true

namespace :google_calendar do
  desc 'Reconcile upcoming bookings and process due Google Calendar synchronization'
  task sync: :environment do
    GoogleCalendarSync.reconcile
    100.times { break unless GoogleCalendarSync.process_next }
  end

  desc 'Run the durable MongoDB-backed Google Calendar worker'
  task work: :environment do
    stopped = false
    %w[INT TERM].each { |signal| Signal.trap(signal) { stopped = true } }
    next_reconcile = 0
    until stopped
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if now >= next_reconcile
        GoogleCalendarSync.reconcile
        next_reconcile = now + 300
      end
      sleep 5 unless GoogleCalendarSync.process_next
    end
  end
end
