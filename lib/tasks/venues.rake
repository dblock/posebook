# frozen_string_literal: true

namespace :venues do
  desc 'Split legacy venue schedules into recurring drawing sessions'
  task split_programs: :environment do
    VenueProgramMigration.call
  end
end
