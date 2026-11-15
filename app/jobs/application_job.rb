# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  after_enqueue do
    QueuedJob.where(id: provider_job_id).first&.update!(active_job_id: job_id) if provider_job_id
  end
end
