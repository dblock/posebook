# Background Jobs

Posebook uses Rails Active Job with [`delayed_job_mongoid`](https://github.com/collectiveidea/delayed_job_mongoid). Queued jobs, execution times, retries, and worker locks persist in the application's MongoDB replica set. No Redis, SQL database, or in-process queue is required. This queue is separate from the Google Calendar outbox, which remains responsible for transactional booking revisions and provider retries.

## Run the Shared Worker

Deploy a Worker component using the same application image, `MONGODB_URI`, `SECRET_KEY_BASE`, and provider configuration as the web application:

```sh
bundle exec rake jobs:work
```

On DigitalOcean App Platform, change the existing Google Calendar Worker run command to this command rather than adding another calendar-only worker. Start with one worker; add processes when capacity or queue isolation requires them. All workers must use the same application version and environment. Startup creates the declared queue indexes. SIGINT and SIGTERM stop after the current job and clear the worker's locks.

The worker handles every named queue by default. Set `JOB_QUEUES=calendar` to handle only calendar work, or a comma-separated list to dedicate workers to selected queues. Ensure every used queue has a worker. A default worker with no filter handles both current and future queues.

For a bounded scheduled or manual run:

```sh
bundle exec rake jobs:run
```

This schedules due recurring work and processes at most 100 jobs. The legacy `google_calendar:work` command remains an alias for the shared worker; `google_calendar:sync` remains a calendar-only manual reconciliation and drain.

## Add a Job

Create an `ApplicationJob` subclass and enqueue it through Active Job:

```ruby
class ExampleJob < ApplicationJob
  queue_as :default

  def perform(venue_id)
    venue = Venue.find(venue_id)
    # Perform the idempotent operation using current authorized state.
  end
end

ExampleJob.perform_later(venue.id.to_s)
ExampleJob.set(wait: 10.minutes).perform_later(venue.id.to_s)
```

Use serializable arguments, preferably string record IDs, and load current data and permissions when executing. Avoid contact snapshots, tokens, and credentials in arguments: queued payloads necessarily persist in MongoDB, including failed jobs. Database access and backups must be restricted accordingly. `ApplicationJob` records the Active Job ID so recurring jobs remain deduplicated through `retry_on` retries.

Enqueue operations inside an ordinary Mongoid model transaction participate in that transaction. For raw MongoDB writes, explicitly pass its session, as the calendar outbox does. Never contact a provider inside a booking transaction or defer critical enqueueing only to an in-process after-commit callback.

Jobs run with at-least-once delivery: a process can die after an external side effect but before deleting its queue entry. Make jobs idempotent, use provider idempotency keys where supported, and recheck cancellation/authorization before sending private information. Split long work into bounded batches: the shared worker enforces a five-minute execution timeout, and abandoned locks become eligible after five minutes. Unhandled failures retry with Delayed Job's progressive delays; after 25 attempts they remain marked failed for operator action. Active Job's `retry_on` and `discard_on` remain available for explicit policies.

## Recurring Work

Register additional job class names and intervals in `config/initializers/background_jobs.rb`. The shared worker checks the registry before each batch; it does not contain provider-specific dispatch code. Recurring schedules and enqueueing share a MongoDB transaction and write barrier, so competing workers do not enqueue duplicate runs. A schedule keeps at most one queued/running/retrying job, including retained failures; missed intervals do not accumulate a backlog. Completed or intentionally discarded jobs become eligible again when their next interval is due.

`GoogleCalendarSyncJob` drains up to 100 due outbox entries every five seconds. `GoogleCalendarReconcileJob` reconciles upcoming bookings every five minutes. Both use the `calendar` queue. Idle polling adds up to another five seconds; busy workers can delay execution. Calendar event identity, private details, invitations, rescheduling, cancellations, revision protection, and provider retry handling remain unchanged.

## Monitor and Recover

Worker logs contain queue-entry IDs, attempt counts, and safe error classifications, not arguments or exception messages. Active Job and Delayed Job's default payload/error logging is disabled. Failed entries retain their payload for controlled retry but store only the exception class in `last_error`.

Inspect counts without printing payloads:

```ruby
QueuedJob.where(failed_at: nil).count
QueuedJob.where(:failed_at.ne => nil).count
```

After correcting a failure, requeue an explicitly selected entry:

```ruby
QueuedJob.find('QUEUE_ENTRY_ID').update!(
  failed_at: nil, attempts: 0, last_error: nil,
  locked_at: nil, locked_by: nil, run_at: Time.current
)
```

Do not mass-delete or blindly replay queued jobs. A retained recurring failure blocks that schedule until explicitly retried or removed. Monitor both queue failures and the program's Google Calendar pending count: Google provider failures remain in the calendar outbox rather than failing the batch job. No automated reminder or new email workflow is enabled by this infrastructure.
