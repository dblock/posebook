# Background Jobs

Posebook uses Rails Active Job with [`delayed_job_mongoid`](https://github.com/collectiveidea/delayed_job_mongoid). Queued jobs, execution times, retries, and worker locks persist in the application's MongoDB replica set. No Redis, SQL database, or in-process queue is required. This queue is separate from the Google Calendar outbox, which remains responsible for transactional booking revisions and provider retries.

## Run the Shared Worker

Deploy a Worker component using the same application image, `MONGODB_URI`, `SECRET_KEY_BASE`, and provider configuration as the web application:

```sh
bundle exec rake jobs:work
```

On DigitalOcean App Platform, add a Worker component using the application Dockerfile and this run command. Start with one shared worker for calendar and other jobs; add processes when capacity or queue isolation requires them. All workers must use the same application version and environment. Startup creates the declared queue indexes. SIGINT and SIGTERM stop after the current job and clear the worker's locks.

The worker handles every named queue by default, including `calendar`, `mailers`, and `maintenance`. Set `JOB_QUEUES=calendar,mailers,maintenance` for all three, or dedicate separate workers to each queue. A calendar-only worker does not send email or clean up application drafts. Ensure every used queue has a worker.

For a bounded scheduled or manual run:

```sh
bundle exec rake jobs:run
```

This schedules due recurring work and processes at most 100 jobs. Use `google_calendar:sync` for calendar-only manual reconciliation and delivery.

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

## Transactional Email

Password recovery, email-change verification, participant invitations, coordinator invitations, and invitations to book again use `EmailDeliveryJob` on `mailers`. Requests report queued email, not completed SMTP delivery. Configure the worker with the web application's SMTP settings, `MAIL_FROM`, `APP_HOST`, and `SECRET_KEY_BASE`. Local development writes email files only when the worker runs.

`EmailDelivery` stores the resource ID, queue-entry ID, original expiry or booking-grant timestamp, and an encrypted bearer token when required. Job arguments contain only its ID; neither queue entries nor the outbox contain plaintext tokens or contact snapshots. Account challenge/profile updates and enqueueing commit together. New invitation links and explicit booking grants remain usable even if their separate email enqueue fails.

The worker reloads current accounts, invitations, permissions, and booking access before sending. Superseded, expired, consumed, revoked, or unauthorized messages are skipped; paused, booked, inactive, or no-longer-entitled participants receive no booking invitation. Recovery and verification links retain their original 30-minute deadline, and registration invitations retain their original 30-day deadline. Expired encrypted tokens are also removed by MongoDB's TTL monitor. SMTP failures or missing worker delivery configuration retain the outbox for safe retries; delivery success or an intentional skip removes it.

SMTP has no atomic acknowledgment shared with MongoDB: a crash after provider acceptance can duplicate an email. Delivery remains at least once, not exactly once. Application-completion reminders use this outbox; automated booking reminders are not enabled.

## Recurring Work

Register additional job class names and intervals in `config/initializers/background_jobs.rb`. The shared worker checks the registry before each batch; it does not contain provider-specific dispatch code. Recurring schedules and enqueueing share a MongoDB transaction and write barrier, so competing workers do not enqueue duplicate runs. A schedule keeps at most one queued/running/retrying job, including retained failures; missed intervals do not accumulate a backlog. Completed or intentionally discarded jobs become eligible again when their next interval is due.

`GoogleCalendarSyncJob` drains up to 100 due outbox entries every five seconds. `GoogleCalendarReconcileJob` reconciles upcoming bookings every five minutes. `GoogleCalendarRsvpPollJob` schedules model invitation-response checks every 12 hours, with one `GoogleCalendarRsvpJob` per synchronized upcoming booking so provider requests remain bounded per job. All use the `calendar` queue. Idle polling adds up to another five seconds; busy workers can delay execution. RSVP checks are read-only, skip fresh duplicate checks, and use the shared queue's safe retries. Calendar event identity, private details, invitations, rescheduling, cancellations, revision protection, and provider retry handling remain unchanged.

`ApplicationDraftMaintenanceJob` runs hourly on `maintenance`. It scans indexed unfinished drafts through a cursor, committing each draft separately so interrupted sweeps retain completed progress. From seven days after the first save, it atomically marks and enqueues one completion reminder for an active verified applicant while their program and venue are active, intake is open, and they are not already a participant. The mail worker rechecks those conditions and the draft's continued existence and status before sending an authenticated resume/abandon link without profile contents or bearer tokens. Delayed reminders expire at the original 30-day deadline. Editing does not reset either age or allow another reminder.

At 30 days, maintenance removes only records still marked Draft without profile-sharing consent, irrespective of account or intake availability. The transaction competes safely with submission: a submitted record and its history survive; a removed draft cannot be recreated from a stale editor revision. Editor revisions bind the draft ID and revision together so an old form cannot overwrite, submit, or abandon a replacement draft whose numeric revision has restarted. Accounts, account photos, memberships, and submitted application/decision history are not deleted. These are elapsed-age thresholds, not exact-time delivery promises: hourly scheduling, worker downtime, retries, and queue load can delay work. Include both `maintenance` and `mailers` when filtering worker queues.

## Monitor and Recover

Worker logs contain queue-entry IDs, attempt counts, and safe error classifications, not arguments or exception messages. Active Job, Action Mailer, and Delayed Job's default payload/error logging is disabled. Failed entries retain their payload for controlled retry but store only the exception class in `last_error`.

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

Do not mass-delete or blindly replay queued jobs. A retained recurring failure blocks that schedule until explicitly retried or removed. Monitor both queue failures and the program's Google Calendar pending count: Google provider failures remain in the calendar outbox rather than failing the batch job. Email provider failures fail their individual queue entries; after an email token expires, request a new link rather than retrying its expired message.
