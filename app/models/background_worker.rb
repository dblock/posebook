# frozen_string_literal: true

class BackgroundWorker
  class SchedulePlugin < Delayed::Plugin
    callbacks do |lifecycle|
      lifecycle.before(:loop) { |_worker| RecurringJobSchedule.enqueue_due }
      lifecycle.after(:perform) do |_worker, job|
        Rails.logger.info("Background job #{job.id}: attempts=#{job.attempts}, error=#{job.last_error || 'none'}")
      end
    end
  end

  def self.build(options = {})
    Delayed::Worker.plugins |= [SchedulePlugin]
    Delayed::Worker.new(options)
  end
end
