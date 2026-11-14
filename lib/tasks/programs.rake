# frozen_string_literal: true

namespace :programs do
  desc 'Convert drawing sessions and model records to programs and participants'
  task migrate_schema: :environment do
    ProgramSchemaMigration.call
  end
end
