# frozen_string_literal: true

namespace :jobs do
  # Replace Delayed Job's task rather than appending a second worker action.
  Rake::Task['jobs:work'].clear_actions if Rake::Task.task_defined?('jobs:work')

  desc 'Run the shared durable MongoDB-backed Active Job worker'
  task work: :environment do
    BackgroundWorker.build.start
  end

  desc 'Schedule recurring jobs and process at most 100 due jobs'
  task run: :environment do
    RecurringJobSchedule.enqueue_due
    success, failure = BackgroundWorker.build.work_off
    puts "Processed #{success} jobs; #{failure} failed."
  end
end
