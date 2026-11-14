# frozen_string_literal: true

namespace :venues do
  desc 'Split legacy venue schedules into recurring drawing sessions'
  task split_sessions: :environment do
    VenueSessionMigration.call
  end
end
