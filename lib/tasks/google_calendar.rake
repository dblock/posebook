# frozen_string_literal: true

namespace :google_calendar do
  desc 'Reconcile upcoming bookings and process due Google Calendar synchronization'
  task sync: :environment do
    GoogleCalendarSync.reconcile
    100.times { break unless GoogleCalendarSync.process_next }
  end

  desc 'Run the shared job worker (compatibility alias)'
  task work: 'jobs:work'
end
