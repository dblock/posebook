# Working on Posebook

Read [Contributing](CONTRIBUTING.md) for commands/workflow and [Design](DESIGN.md) for the current domain and invariants. Follow [UI Conventions](docs/ui-conventions.md) for interface changes and [Upgrading](UPGRADING.md) for compatibility changes.

## Find the Existing Flow

Before implementing a request, trace the relevant route, controller, operation model, tests, and worker rechecks. If behavior exists, identify its enforcing code/tests and fix only the gap. Update documentation that failed to point to it; do not build a parallel flow.

Controllers are thin; operations and read models live in `app/models/`:

| Area                        | Entry Points                                                                                                                                    |
| ---                         | ---                                                                                                                                             |
| Booking/schedule            | `BookingMutation`, `OrganizerBookingMutation`, `AttendanceMutation`, `ProgramScheduleMutation`, `ProgramSettingsUpdate`                         |
| Participant access/settings | `ParticipantAccessMutation`, `ParticipantDetailsUpdate`, `InvitationAcceptance`, `LocationActivation`                                           |
| Applications                | `ParticipantApplicationWorkflow`, `ApplicationDraftMaintenance`                                                                                 |
| Accounts/privacy            | `AccountSettings`, `PublicProfile`, `Current`                                                                                                   |
| Email/jobs                  | `EmailDelivery`, `EmailDeliveryMessage`, `RecurringJobSchedule`                                                                                 |
| Reads                       | `BookingAccess`, `ProgramRoster`, `ProgramCalendar`, `ParticipantDashboard`, `ParticipantHistory`, `AuditHistory`, `CursorPage`, `PhotoGallery` |

Reuse shared view helpers/partials and `spec/support/` fixtures/browser helpers. Request, browser, integration, and script tests live in their matching `spec/` directories.

## Data and Authorization

MongoDB is the only database. Use public Rails, Mongoid, and provider APIs; do not add SQL-backed components or Redis. Runtime/support versions and setup commands are in Contributing.

Tests use only `MONGODB_TEST_URI` with `posebook_test` or a `posebook_test_` prefix, never development/production fallback. Track and remove only owned records/files; never purge databases, collections, or shared Docker resources. Use fake providers and synthetic images, not real emails, calendar writes, or personal data.

Use one User model with scoped memberships. Only first-user bootstrap grants `system_admin`. Public registration closes afterward; invitations or email-verified application preparation create ordinary accounts. Never accept role fields in public forms or grant membership through email verification.

Authorize private routes through current account state and scoped visibility/management queries. Public visibility is not private access. Venue coordinators inherit their programs; program coordinators cannot assign peers or change parents/siblings. Revoking one role preserves independent memberships and retained history.

Inactive parents block new bookings/date changes without changing child flags or canceling commitments. Retain manager/upcoming-participant access and cancellation/attendance rights. Protect system admins from deactivation. Filter contacts, gender, private notes, and authentication secrets from logs.

Invitations remain hashed, expiring, single-use, and optional-email-bound. Acceptance rechecks the recipient, current sender authority, and program scope, atomically with account creation and membership. Preserve wrong-account return paths and require explicit existing-account coordinator promotions.

## Transactional Writes

Booking, schedule, attendance, program settings, and participant access mutations share the program schedule write barrier. Reload authority/state on retries; venue activation writes its venue barrier first. Keep external providers outside transactions.

Retain every Booking and its original date, explanations, saved times, and replacement links. Only disposable claims expire. Preserve unique program/date and program/user claim indexes, and update the existing claim on replacement. Compute civil dates in the program time zone and save instants in UTC.

Booking forms submit the displayed `lock_version`; never substitute a current version for missing/stale input or refresh submitted intent during retries. Schedule confirmations also check the displayed program revision. Conflicts return fresh authorized pages. Repeated positive attendance confirmations must not reverse newer organizer changes.

First participation grants one booking cycle; completion exhausts it. Cancellation/rescheduling preserve grants; pause preserves bookings but blocks new scheduling, and resume does not renew access. Repeat registration invitations cannot bypass these rules. Bulk grants span every page and recheck eligibility.

Participant editing changes only membership display overrides, Instagram/photo hiding, and scoped private notes, not the account. Save audited changes together with fresh manager authorization, without changing schedule revisions or booking rights. Private notes never reach participants, other programs, or providers.

## Applications and Messaging

Drafts are owner-only, grant no review/photo access, and stage profile fields until explicit consented submission. Bind revisions to draft ID and version for save/submit/abandon; stale forms must not recreate removed drafts. Photos use existing authorized storage outside submission transactions and survive abandonment.

Pending and rejected applications with review consent grant scoped reading, never editing. Withdrawal revokes application-only access on every image request and prevents acceptance. Preserve identity snapshots, append-only decisions/events, private reviewer notes, and optimistic decision revisions. Acceptance uses the existing first-cycle membership path.

Required application/decision/admission email outboxes and ID-only jobs join the workflow transaction through `EmailDelivery.enqueue_in_transaction` and its active session. Enqueue failures roll back the workflow; do not nest transactions or send SMTP there. Optional invitation-email failure must preserve its usable private link/grant.

Notify active assigned coordinators once per person, not every global admin. Workers recheck source, current state, account, assignment, consent/access, and original expiry before sending. Keep reviewer notes and contacts out of admission alerts. Distinguish queued from delivered and retain at-least-once delivery semantics.

Draft maintenance uses creation or reopening age: one reminder from seven days, cleanup from 30 days. Do not reset age on edits, invalidate editor revisions for reminders, use blanket TTL deletion, or remove accounts/photos/submitted history. Reopened draft cancellation or expiry restores the retained withdrawn submission. Cleanup must transact against submission. Use the shared recurring scheduler and `maintenance`/`mailers` queues.

Automated booking reminders and SMS remain disabled; transactional account/invitation/application messages are separate. New jobs use the shared MongoDB-backed worker, minimal ID arguments, current-state rechecks, and idempotent effects. Preserve the separate transactional Google Calendar outbox.

## Privacy, Photos, and Audit

Public output uses effective public identity and consented Instagram helpers, never raw account names/handles or private contacts. Inactive accounts are anonymous. Program identity overrides must not mutate global profile preferences.

Store optimized images and thumbnails in GridFS, never ephemeral disk. Preserve content/size/dimension validation, metadata removal, proportional full images, concurrent account uploads, and no application photo-count cap. Scope location photos to their owner; consented organizer read access does not permit editing account galleries.

Authorize every image request before bytes or 304. Immutable variant IDs supply private, zero-freshness, must-revalidate ETags; never allow shared caching or validation-free reuse. Owner/visibility changes invalidate request-local photo snapshots. Keep source artwork and rendering instructions in Design.

Audited business changes use ordinary saves and scoped `Current` actor context; raw/atomic writes bypass `mongoid-history`. Never track authentication secrets/challenges. Admin History resolves only whitelisted classes and current tracked fields, batches subjects, and handles deletion without broken links. No arbitrary class resolution, raw payload disclosure, or undo routes.

## Read Models and Interface

Use request-local batched snapshots, not persistent permission/private HTML caches. Mutations always read fresh state. Calendar fragments require a matching freshly authorized access context; otherwise replace the full page to remove stale private controls.

Use `CursorPage`/`mongoid-scroll`, never offsets. Supply an authorized scope, one sort field, and a compound index ending in `_id`. Cursors do not grant access. Preserve filters/action cursors, reset on filter changes, and render `shared/pagination` outside nonempty-results blocks so empty ranges can return to First. Preserve reverse-sort/ID traversal and millisecond-rounded Time boundaries.

Forms and navigation must work without JavaScript. Interface changes require real system specs, applicable desktop/phone/narrow layouts, and hosted PR screenshots of meaningful states. Reuse existing browser helpers; keep captures out of Git.

## Validation and Documentation

Run the Contributing checks before committing/pushing; documentation-only changes need lint, not application/package reruns. Keep Test, Lint, and Package workflows separate, use explicit inline `matrix.entry` combinations, and retain Coveralls and PR-only Danger checks.

Keep DESIGN about current architecture and rationale, not implementation history, UI copy, or test inventories. Put instructions in existing user/operations guides, contributor commands in Contributing, and actionable coding constraints here. Keep README brief and link project documentation through Contributing.

Use Title Case headings/display names and one source line per Markdown paragraph. Review spelling vocabulary and narrow lint exceptions; fix typos instead of suppressing checks. Add meaningful improvements to the changelog with the verified PR number.
