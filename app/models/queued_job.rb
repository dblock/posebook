# frozen_string_literal: true

class QueuedJob < Delayed::Backend::Mongoid::Job
  field :active_job_id, type: String
  index({ active_job_id: 1 })

  def error=(exception)
    super
    self.last_error = exception.class.name
  end
end
