# frozen_string_literal: true

class RecurringJobSchedule
  include Mongoid::Document

  field :_id, type: String
  field :next_run_at, type: Time
  field :queued_job_id, type: String
  field :revision, type: Integer, default: 0

  def self.enqueue_due(schedules = Rails.application.config.x.recurring_jobs)
    schedules.each do |name, interval|
      job_class = name.to_s.constantize
      next if Delayed::Worker.queues.any? && Delayed::Worker.queues.exclude?(job_class.queue_name)

      find_or_create_schedule(job_class.name).enqueue(interval)
    end
  end

  def self.find_or_create_schedule(name)
    collection.find(_id: name).update_one(
      { '$setOnInsert' => { next_run_at: Time.current, revision: 0 } }, upsert: true
    )
    find(name)
  end

  def enqueue(interval)
    self.class.with_session do |session|
      session.with_transaction do
        reload
        inc(revision: 1)
        write_job(interval) if ready?
      end
    end
  end

  private

  def ready?
    next_run_at <= Time.current && (queued_job_id.nil? || !QueuedJob.exists?(active_job_id: queued_job_id))
  end

  def write_job(interval)
    job = id.constantize.perform_later
    update!(queued_job_id: job.job_id, next_run_at: Time.current + interval)
  end
end
