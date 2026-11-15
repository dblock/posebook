# frozen_string_literal: true

Delayed::Worker.destroy_failed_jobs = false
Delayed::Worker.max_run_time = 5.minutes
Delayed::Worker.logger = nil
Delayed::Worker.queues = ENV.fetch('JOB_QUEUES', '').split(',').map(&:strip).reject(&:empty?)

Rails.application.config.to_prepare { Delayed::Worker.backend = QueuedJob }

Rails.application.config.active_job.logger = ActiveSupport::Logger.new(File::NULL)
Rails.application.config.action_mailer.logger = ActiveSupport::Logger.new(File::NULL)
Rails.application.config.x.recurring_jobs = {
  ApplicationDraftMaintenanceJob: 1.hour,
  GoogleCalendarSyncJob: 5.seconds,
  GoogleCalendarReconcileJob: 5.minutes,
  GoogleCalendarRsvpPollJob: 12.hours
}
