# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe BackgroundWorker, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  let(:queue) { "worker-spec-#{SecureRandom.hex(6)}" }
  let(:venue) { create_venue }
  let(:job_class) do
    Class.new(ApplicationJob) do
      class_attribute :action

      def perform(*)
        self.class.action.call(*)
      end
    end
  end

  around do |example|
    previous_queues = Delayed::Worker.queues
    travel_to(Time.utc(2026, 11, 14, 15)) { example.run }
  ensure
    Delayed::Worker.queues = previous_queues
  end

  before do
    stub_const(:WorkerProbeJob.to_s, job_class)
    job_class.queue_as(queue)
    job_class.action = ->(id, name) { Venue.find(id).update!(name: name) }
    Delayed::Worker.queues = [queue]
  end

  after do
    QueuedJob.where(queue: queue).delete_all
    RecurringJobSchedule.where(id: job_class.name).delete_all
  end

  def worker
    described_class.build(queues: [queue]).tap { |instance| instance.name = SecureRandom.uuid }
  end

  def schedule
    RecurringJobSchedule.enqueue_due(job_class.name => 1.minute)
  end

  it 'persists serialized Active Jobs and respects scheduled execution' do
    job = job_class.set(wait: 1.minute).perform_later(venue.id.to_s, 'Updated by a job')
    expect(QueuedJob.find(job.provider_job_id)).to have_attributes(queue: queue, active_job_id: job.job_id)
    expect(worker.work_off).to eq([0, 0])
    travel 1.minute
    expect(worker.work_off).to eq([1, 0])
    expect(venue.reload.name).to eq('Updated by a job')
    expect(QueuedJob.where(active_job_id: job.job_id)).to be_empty
  end

  it 'rolls back queued jobs when the surrounding MongoDB transaction fails' do
    venue
    expect do
      Venue.with_session do |session|
        session.with_transaction do
          job_class.perform_later(venue.id.to_s, 'Never delivered')
          raise 'Roll back'
        end
      end
    end.to raise_error('Roll back')
    expect(QueuedJob.where(queue: queue)).to be_empty
    expect(venue.reload.name).not_to eq('Never delivered')
  end

  it 'retries failures without exposing error messages or arguments to storage or logs' do
    output = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(output))
    job_class.action = ->(*) { raise 'Private model@example.test +12025550101 token' }
    job = job_class.perform_later(venue.id.to_s, 'Private argument')
    expect(worker.work_off).to eq([0, 1])
    queued = QueuedJob.find(job.provider_job_id)
    expect(queued).to have_attributes(attempts: 1, last_error: RuntimeError.name, locked_by: nil)
    expect(queued.run_at).to be > Time.current
    expect(output.string).to include(RuntimeError.name)
    expect(output.string).not_to include('model@example.test', '+12025550101', 'Private argument', 'token')
    job_class.action = ->(id, name) { Venue.find(id).update!(name: name) }
    travel_to(queued.run_at + 1.second)
    expect(worker.work_off).to eq([1, 0])
    expect(venue.reload.name).to eq('Private argument')
  end

  it 'retains exhausted failures for explicit inspection and retry' do
    job_class.action = ->(*) { raise 'Provider unavailable' }
    job = job_class.perform_later
    QueuedJob.find(job.provider_job_id).set(attempts: Delayed::Worker.max_attempts - 1)
    expect(worker.work_off).to eq([0, 1])
    queued = QueuedJob.find(job.provider_job_id)
    expect(queued.failed_at).to be_present
    expect(queued.last_error).to eq(RuntimeError.name)
    expect(worker.work_off).to eq([0, 0])
  end

  it 'allows only one worker to claim a job and recovers expired locks' do
    job = job_class.perform_later(venue.id.to_s, 'Processed once')
    first = worker
    second = worker
    results = [first, second].map { |instance| Thread.new { instance.work_off } }.map(&:value)
    expect(results).to contain_exactly([1, 0], [0, 0])
    expect(venue.reload.name).to eq('Processed once')
    expect(QueuedJob.where(active_job_id: job.job_id)).to be_empty
    abandoned = job_class.perform_later(venue.id.to_s, 'Recovered')
    queued = QueuedJob.find(abandoned.provider_job_id)
    queued.set(locked_by: 'dead-worker', locked_at: Time.current)
    expect(worker.work_off).to eq([0, 0])
    queued.set(locked_at: 6.minutes.ago)
    expect(worker.work_off).to eq([1, 0])
    expect(venue.reload.name).to eq('Recovered')
  end

  it 'atomically schedules one recurring job across competing workers and resumes after completion' do
    job_class.action = ->(*) {}
    RecurringJobSchedule.create!(id: job_class.name, next_run_at: Time.current)
    2.times.map { Thread.new { schedule } }.each(&:value)
    expect(QueuedJob.where(queue: queue).count).to eq(1)
    travel 2.minutes
    schedule
    expect(QueuedJob.where(queue: queue).count).to eq(1)
    expect(worker.work_off).to eq([1, 0])
    schedule
    expect(QueuedJob.where(queue: queue).count).to eq(1)
  end

  it 'keeps recurring retries deduplicated when Active Job replaces the queue record' do
    job_class.retry_on(RuntimeError, wait: 10.minutes, attempts: 2)
    job_class.action = ->(*) { raise 'Retry later' }
    schedule
    original = QueuedJob.where(queue: queue).first
    expect(worker.work_off(1)).to eq([1, 0])
    replacement = QueuedJob.where(queue: queue).first
    expect(replacement.id).not_to eq(original.id)
    expect(replacement.active_job_id).to eq(original.active_job_id)
    travel 2.minutes
    schedule
    expect(QueuedJob.where(queue: queue).count).to eq(1)
    expect(QueuedJob.where(queue: queue).first.id).to eq(replacement.id)
  end

  it 'does not advance a recurring schedule if enqueueing fails inside its transaction' do
    allow(job_class).to receive(:perform_later).and_wrap_original do |original|
      original.call
      raise 'Enqueue interrupted'
    end
    expect { schedule }.to raise_error('Enqueue interrupted')
    expect(QueuedJob.where(queue: queue)).to be_empty
    expect(RecurringJobSchedule.find(job_class.name)).to have_attributes(queued_job_id: nil, revision: 0)
  end

  it 'does not schedule recurring work for queues excluded from this worker' do
    Delayed::Worker.queues = ['another-queue']
    schedule
    expect(QueuedJob.where(queue: queue)).to be_empty
    expect(RecurringJobSchedule.where(id: job_class.name)).to be_empty
  end

  it 'starts only the shared worker through the legacy task after loading the gem tasks' do
    original_application = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    shared = instance_spy(Delayed::Worker)
    legacy = instance_spy(Delayed::Worker)
    allow(described_class).to receive(:build).and_return(shared)
    allow(Delayed::Worker).to receive(:new).and_return(legacy)
    Rake::Task['google_calendar:work'].invoke
    expect(shared).to have_received(:start).once
    expect(legacy).not_to have_received(:start)
  ensure
    Rake.application = original_application
  end
end
