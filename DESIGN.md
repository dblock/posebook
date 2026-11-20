# Design

## Scope and Domain

Posebook manages invitation-first participation in recurring programs. Payments, attendee reservations, and public participant directories are out of scope. Email covers accounts, invitations, applications, booking changes, and configurable booking reminders. Google Calendar messages are separate; SMS is not implemented.

`Venue` is a physical location; `Program` owns a recurring schedule, time zone, pay, private instructions, booking rules, roster, invitations, and calendar. `Booking` is a retained dated reservation, not a separate event resource. Authentication sessions are unrelated to programs. Configurable program/participant labels change presentation, never roles or booking policy.

Venues and programs have optional, audited public descriptions of at most 5,000 characters. Programs also have optional, audited application instructions of at most 5,000 characters, shown publicly instead of the description on application preparation and application forms and omitted when blank. Descriptions, application instructions, and private program instructions share sanitized Markdown rendering; raw HTML, unsafe links, and embedded images are excluded. Existing instructions remain private and are never copied into descriptions. Pay is member-only, and the booking horizon appears only in settings.

One `User` identity has independent venue and program memberships. Global roles contain only system-wide authority:

| Role                | Authority                                                                                                    |
| ---                 | ---                                                                                                          |
| System admin        | Manage all records and assign venue coordinators.                                                            |
| Venue coordinator   | Manage the venue and all its programs; assign program coordinators.                                          |
| Program coordinator | Manage assigned programs, participants, bookings, and dated exceptions; cannot assign peers or parent roles. |
| Participant         | Manage their own bookings independently in each program.                                                     |

`Program.visible_to` and `Program.managed_by` scope reads and private actions. Public visibility never grants membership or mutation rights. Unique memberships preserve independent roles when one capability is revoked.

Venues and programs use `mongoid-slug` with retained slug history and ID lookup under `/venues` and `/programs`. Authentication uses `/session`; retired `/sessions` and root shortcuts are not aliases. Startup creates declared indexes only. Required manual conversions belong in [Upgrading](UPGRADING.md).

Program overview, calendar, and retained booking history have distinct paths. Calendar and history routes reuse the existing program-page lifecycle and authorization. Only the route selects the page; filters, calendar months, and cursors remain query state.

## Accounts and Public Identity

Blank-installation registration creates the first system admin. A fixed bootstrap document ID prevents competing claims without requiring a transaction. Registration then closes; later accounts require personal invitations or email-verified application registration for active, opt-in programs. Public forms never accept roles.

BCrypt passwords have a 12-character minimum and 72-byte maximum. Encrypted, HTTP-only, same-site session cookies rotate on login/logout and carry a per-user session version. Ordinary sessions last seven days. Optional Remember Me credentials restore sessions without an application deadline; their renewable browser cookies request twenty years, subject to browser limits.

Logout and unchecked sign-in clear remembered credentials. Password changes retain the current ordinary session but revoke older sessions and the remembered choice. Confirmed email changes, resets, and deactivation revoke sessions and remembered credentials. Every restoration checks the current account and session version.

Recovery and email-change tokens are random, stored as SHA-256 digests, single-use, and valid for 30 minutes. Consumption and credential changes are atomic; GET never consumes a token. Email changes require the current password and verification at the new address. Admin email edits apply immediately, revoke sessions/challenges, and do not verify ownership. Recovery responses conceal whether an address exists. Rails authentication rate limits use the current per-process memory cache.

Phone and gender are required; neither is verified. Phone input normalizes to international `+` digits, with ten-digit numbers interpreted as US/Canada. Gender is private and audited, used only in configured booking rules and authorized organizer views.

Public identity uses the display name or "To be announced", never the account name. Instagram handles normalize from handles or profile URLs; derived public links require an active account and tagging consent. Registration defaults tagging on and requires a handle when selected. Inactive accounts expose neither public identity nor photos. Private calendars/history may fall back to the account name when the display name is blank.

Program managers can override a participant's display name and hide public Instagram/photos for that program through `ProgramMembership`. They cannot edit the account there. Membership notes are manager-only and never sent to providers. Overrides and notes save together with audit history but do not change schedule revisions or booking grants.

Deactivation retains accounts, photos, memberships, and bookings while revoking authentication and public sharing. It does not cancel commitments or external invitations; reactivation restores saved preferences. System admins cannot be deactivated until role transfer exists. Admin pages reuse profile views and permissions; another user's booking views are read-only, and password recovery never exposes or sets their password.

## Invitations and Applications

Personal participant and coordinator invitations are revocable, single-use, and valid for 30 days. A specified email restricts acceptance to that address; a blank email creates a private bearer link without email delivery. Invitations store token digests; only the encrypted delivery outbox retains a token for mail. Wrong-account sign-in preserves the invitation while switching accounts.

Acceptance atomically consumes the token, creates an account if necessary, and adds the scoped membership without dropping existing roles. Coordinator acceptance rechecks the sender's active delegation authority. Venue delegation requires a system admin; program delegation requires an admin or parent venue coordinator. Existing-account promotions require explicit confirmation. No coordinator invitation grants global roles.

Participant acceptance grants the first booking cycle only when adding participation for the first time. Repeat invitations cannot renew consumed grants or bypass pauses. Optional email enqueue failures preserve private invitation links and explicit booking grants.

### Application Lifecycle

Program intake is opt-in. `ApplicationRegistration` verifies an email using a hashed, single-use, 30-minute token; verification creates or confirms an ordinary account, not membership, booking access, or profile-review consent. Consumption rechecks the account, email, active program/venue, and open intake.

Applicants prepare account details, photos, and an application in one editor. GET creates nothing. First save creates an owner-only Draft; incomplete profile fields stay staged until explicit submission validates and atomically applies them with consent, an identity snapshot, history, and notification outboxes. Account photos are saved separately and survive abandonment.

Draft saves, submission, and abandonment require a revision bound to both draft ID and version. Stale forms cannot overwrite newer work or recreate removed/replacement drafts. Drafts are excluded from coordinator lists, review routes, and application-only photo access.

Pending and rejected applications with consent permit scoped coordinators to read current private applicant profiles/photos, not edit them. Withdrawal immediately removes application-only access and prevents acceptance; retained submission snapshots do not expose later identity changes. Acceptance switches to ordinary participant permissions.

`ParticipantApplication` stores current state, decision revision, and submission identity snapshots. Decisions recheck the submitted revision and manager authority inside a transaction. Acceptance uses the shared schedule lock and initial-membership grant path, preserving existing roles, pauses, and consumed grants. Intake closure retains existing applications.

Every lifecycle transition appends a `ParticipationEvent` in the same transaction: initial draft creation, submission, decisions, withdrawal, reopening, cancellation, and expiry. Repeated cycles retain separate entries; failed or stale transitions and ordinary draft edits add none. Minimal transition metadata survives deletion of a never-submitted draft without retaining its form contents. Automatic expiry has no human actor. Coordinator histories allow only shared submission, decision, withdrawal, and invitation-acceptance actions, never private draft transitions; reviewer notes remain manager-only.

Submission requires configured email and an active assigned coordinator. Submission/decision history and ID-only notification jobs commit in the workflow transaction through `EmailDelivery.enqueue_in_transaction`. Enqueue failure rolls back the workflow. Assigned venue/program coordinators receive separate messages, deduplicated across assignments; global admins are not automatically subscribed. Applicants receive decision messages without reviewer notes.

Accepted applications and personal invitations also queue separate coordinator admission alerts in the acceptance transaction. Private invitation acceptance remains available without email or assigned recipients. Workers recheck source, state, account, participation, and recipient assignment; withdrawn or superseded notices are discarded.

Applicants can reopen only their own withdrawn application as a private draft while intake is open. Reopening checks the current revision, retains submitted history and the previous message, and requires fresh consent before another submission. Application details are read-only and show the program and history. State controls live in the shared homepage and profile table, with Resubmit also on withdrawn details; submission and cancellation return to the profile applications list.

Management homepages include a cursor-paginated submitted-application queue scoped through `Program.managed_by`: all programs for system administrators and assigned or inherited programs for coordinators. Status filtering defaults to Pending, supports individual submitted states and All, remains available for empty results, and preserves the selected status across pagination. Homepage and program application filters use normal GET forms enhanced with region-only fetches, aborting stale requests and preserving URL and browser history without a document reload. Cursors cannot cross status or authorization scopes. Every filter excludes drafts, uses retained applicant identity snapshots, and links to the existing authorized review workflow. Personal application controls remain separate; no manager receives draft access.

Hourly draft maintenance queues one completion reminder, by default from seven elapsed days after initial creation or reopening, and expires draft edits from 30 days. The reminder delay is configurable from zero through 29 days; cleanup is not. Ordinary saves do not reset either age. A reopened draft retains its prior withdrawn submission, which is restored on cancellation or expiry instead of deleting history. Workers reject reminders and notifications from superseded submission cycles. Reminder enqueueing is transactional without invalidating the editor revision; cleanup serializes against submission and preserves accounts, photos, and submitted history. See [Background Jobs](docs/background-jobs.md).

## Scheduling and Booking

Programs default to Mondays at 09:00 UTC, no end time, zero informational pay, and a six-month horizon. Earlier end times mean the next day; equal start/end times are invalid. Civil-date calculations use the program's IANA time zone; saved instants use UTC. Nonexistent daylight-saving times are rejected; repeated times use Rails' daylight-saving preference.

The inclusive booking window starts at the later of local today or optional `first_bookable_date`, then advances by the configured calendar-month horizon. This cutoff restricts new bookings/replacements, not when sessions occur or existing commitments. Public summaries and schedule maintenance can retain earlier actual sessions. Participants may hold one upcoming booking per program, with no cross-program conflict constraint.

`ProgramScheduleException` has a unique program/date index and open, closed, or regular mode. Changes require an explanation of at most 200 characters. Open overrides weekday/times; closed blocks the date; regular restores the recurring rule without deleting history. Closing an occupied date atomically cancels its booking and releases its claim. Time edits append attributed old/new UTC values. Regular schedule edits update upcoming regular bookings while preserving dated overrides.

Gender rules optionally prohibit repeats in immediately adjacent scheduled sessions. Both neighbors count, including a completed predecessor; an unbooked session breaks the sequence. Dated openings count, closures and nonexistent start times do not. Rescheduling excludes the replaced booking. Later profile/rule/schedule edits do not cancel existing bookings.

Rules implement `evaluate(date, user)`, returning `nil` or an immutable `BookingRuleDecision` with code, localized message, and override policy. Participants cannot override; organizers explicitly acknowledge permitted conflicts with a retained private explanation. Missing gender cannot be overridden. Calendars and transactional mutations share the rule implementation without publishing gender.

### Ledger and Concurrency

`Booking` retains program/user, original date, saved time zone and UTC start/end/expiry, status, actor/explanation/time, attendance/time-change history, and previous-booking links. Cancellation closes the record; rescheduling closes it and creates a linked replacement. Application deletion is guarded. Historical bookings are never removed by expiry or rewritten by ordinary settings changes.

`BookingClaim` holds disposable active pointers with unique program/date and program/user indexes. A replica-set transaction commits ledger and claim changes together. Replacements update the existing claim rather than reusing a deleted unique key inside a transaction. Expired claims are removed before mutations. Completion/expiry uses the saved end, or saved local end of day when no end exists, without a rollover job. Legacy bookings without a start instant retain their 18:30 local fallback.

Booking, attendance, access, schedule, and program-setting mutations share a program revision write barrier and reload state on transaction retries. Venue activation writes the venue before the program barrier. These locks prevent closures, time edits, pauses, and deactivation racing a booking. Failed operations roll back claims, replacements, revisions, history, and outboxes together.

Participant date confirmation carries the schedule revision. Booking edits/cancellation/attendance also atomically compare and increment `lock_version`; missing stored versions mean zero, but missing/malformed submitted revisions are rejected. Retries preserve the original submitted revision, not refreshed intent. Conflicts return a fresh authorized page; foreign records remain hidden. Schedule time changes invalidate open booking forms.

Claims are rechecked inside the transaction so competing bookings produce a friendly date-taken result. Failed replacements retain the original booking. Organizer reassignment excludes its original claim. Unique indexes remain the final safeguard.

### Booking Grants and Attendance

Participation alone does not grant repeat bookings. Membership stores the booking grant, actor, pause state, and private explanation. A grant survives cancellation/rescheduling and is exhausted when the booked cycle completes. Pauses block new bookings/rescheduling but preserve reservations, cancellation, and attendance; resume restores unused permission only. Legacy reservations may finish their existing cycle without an invitation timestamp; no automatic grant backfill runs.

Individual and bulk grants recheck active accounts, pauses, and upcoming bookings inside the schedule transaction. Bulk actions cover the whole program, not the current roster page. Grant history and pause reasons are audited; private explanations never reach participant pages or request logs.

Attendance confirmation opens at the previous scheduled session's end by default, configurable per program to calendar days before at a chosen local time, and closes at the saved start. Unbooked dates and dated exceptions count as sessions; a preceding saved booking supplies its retained end, with local midnight as the fallback when no end was configured. Calculations retain the upcoming booking's saved time zone. The email toggle does not disable attendance confirmation itself. Attendance is separate from the reservation's persisted `confirmed` status. Participants can confirm but not clear attendance; repeated positive confirmations are idempotent and cannot reverse a later organizer clear. Organizers explicitly set/clear attendance when creating or replacing upcoming bookings; participant replacements start unconfirmed.

Unconfirmed bookings at the inclusive five-calendar-day rescheduling cutoff direct participants to organizers and show private overdue warnings to managers. Positive attendance is public; contacts, overdue follow-up, and change history are private. Deadlines use saved booking dates/time zones. Terminal booking states take display precedence while retaining attendance history.

### Booking Notifications

Admin, venue, and program settings hold independently enabled notification templates and timing. Every scheduled booking notification can use the previous scheduled session's end or a calendar-day offset and local clock; timing inherits independently of message content. Confirmation requests follow the opening checkpoint; unconfirmed reminders default to five calendar days before at noon, final session reminders to one day before at noon, and coordinator overdue alerts to disabled. Changing another reminder's timing does not move confirmation opening. Immediate booking, replacement, cancellation, time/location change, and attendance transitions record per-recipient notices in their mutation transaction. Venue edits share the venue/program write barriers and notify upcoming bookings when their name/address changes. Assigned coordinators are deduplicated and the acting coordinator is excluded; global administrators are not automatically recipients.

Minute maintenance records due reminders and queues pending notices through the existing transactional email outbox. Unique event/recipient keys prevent duplicate concurrent scheduling. Workers recheck settings, current booking signature, attendance transition, current assignment/account/access, original expiry, and participant reminder preference. Reminders skip missed local-date checkpoints, overlapping same-day participant messages, and sessions that have started. Late booking emails include an available confirmation prompt rather than a second email. Paused intake/new-booking access does not suppress valid commitments. Delivery records retain pending, queued, sent, skipped, or failed state without contact snapshots; SMTP remains at least once.

All application emails use editable plain-text subjects and bodies with a per-kind placeholder vocabulary. Audited admin defaults live in a singleton `NotificationDefaults` document, venue overrides in `Venue.notification_settings`, and program overrides in `Program.notification_settings`. Fields inherit independently, unchanged inherited values are not materialized, and clearing content restores the current parent template. System account/verification settings are admin-only and cannot disable delivery; required action links cannot be removed or placed in subjects. Scope-specific controllers share the list/editor/preview implementation, while updates retain fresh authorization and transactional write barriers.

Preview and delivery share substitution and escaped text/link rendering. Previews use synthetic recipients and never send email or change settings. Unknown placeholders and subjects containing line breaks are rejected. Private change explanations and reviewer notes are unavailable as placeholders. Scheduled participant emails append a signed preference link whose GET only displays a confirmation form; disabling reminders requires POST/PATCH. Profile notification preferences separately govern booking reminders, draft reminders, and optional coordinator alerts, including delivery-time rechecks. Security emails, invitations, application decisions, and immediate service updates remain separate. Google-generated Calendar content and delivery-provider credentials are not template settings.

## Public Pages and Interface

Guests see upcoming sessions for active programs/venues over the next two weeks, ordered by start time. Public program overviews show the next real session in the local window, followed by the venue card with its public photos, address, and links. Both expose only the booked participant's effective public identity and consented Instagram, never full rosters, contacts, private instructions/pay, cancellations, or internal schedule reasons.

Signed-in homepages show personal bookings, viewable participant programs, and authorized management programs. Profile Bookings lists eligible booking programs; Profile Programs lists managed programs, including inactive ones. Paused/booked memberships can remain visible without gaining new booking rights. Public calendars show current public identity even for completed bookings; month navigation begins at the current local month.

Only system admins activate venues; admins and parent venue coordinators activate programs. Inactive parents block children without changing their flags. Inactive locations disappear publicly but remain available to managers and upcoming booked participants. Existing cancellation, attendance, and history access survive; bookings and external invitations are not canceled.

Server-rendered forms and links work without JavaScript. Enhancements provide calendar fragments, in-place editing, galleries, clipboard controls, and pending-action feedback. Calendar fragments require an exact match against freshly authorized viewer/schedule/attendance context; changes force full-page replacement to remove stale private controls. No shared cache contains private HTML or permissions.

Navigation, responsive layout, status labels, shared controls, and browser-test conventions live in [UI Conventions](docs/ui-conventions.md); user flows live in the [user guides](README.md#user-guides). Public policy drafts identify Vestris LLC. and need legal review before reliance.

## Photos and Caching

Account galleries use embedded metadata; venue/program galleries use separate `VenuePhoto`/`ProgramPhoto` documents. Optimized images and thumbnails live in MongoDB GridFS without an application count cap. Atomic account-photo appends preserve concurrent uploads.

Uploads validate actual JPEG/PNG/WebP content, 10 MB, and 40-megapixel limits. libvips corrects orientation, strips metadata, and creates a proportional WebP bounded to 1600 pixels plus a 400-pixel square thumbnail; originals are discarded. Failed uploads/deletions clean up their own variants. Backups must include `photos.files` and `photos.chunks`.

Photos default public. Owners/admins manage account photos; assigned organizers may read private participant photos, including consented pending applicants, but cannot edit them. Location managers edit only their authorized galleries. Primary selection makes a photo public; making it private clears the preference. Deleted/unset selections fall back to the first public photo. Program cards fall back to public venue photos, then local placeholders.

Image bytes are immutable: replacement creates new GridFS IDs. Every image request authorizes current account, location, role, visibility, and deletion state before considering conditional headers. Responses use `Cache-Control: max-age=0, private, must-revalidate` and a strong ETag per full-image/thumbnail file ID. Authorized matches return 304 without reading GridFS bytes; shared caching and reuse without validation are prohibited.

The photo dialog loads only the selected full-size image and uses public series for cards. Galleries navigate only their visible photos. Ordinary image links remain the no-JavaScript fallback. There is no persistent server-side byte cache.

## Read Models and Pagination

Dashboards, rosters, cards, and session lists use request-local snapshots to batch bookings, access history, venues, primary/public photo IDs, and schedule exceptions. Public session identity reads project only booked user/program pairs. Empty supplied snapshots prevent fallback queries. Photo preferences invalidate owner-local snapshots; calendar instances cache date calculations for that render only. Mutations always query fresh transactional state.

`CursorPage` uses `mongoid-scroll` for rosters, invitations, applications, participation/booking history, and admin audit history. Rosters contain 25 rows; other pages contain 50. Queries use one sort field and an immutable ID tie-breaker with matching compound indexes. Booking history orders by date then ID; rosters by creation ascending; other histories by creation descending.

First, Previous, and Next are server links. Previous reverses both sort directions, runs a forward scroll, then reverses display order; the gem's previous-direction aggregation mishandles ties and eager loading. Decoded Time boundaries are rounded to MongoDB milliseconds to avoid float decoding moving a boundary below its stored value. One extra row detects more results; a bounded existence query checks the opposite direction.

Signed cursor purposes bind the model, authorized selector, and sort. Tampered, invalid, or cross-scope cursors restart at First; authentication is rechecked on every request. Filters reset cursors, actions preserve them, and bulk operations cover the whole program. Empty ranges retain First. Inserts/deletions before a boundary do not shift results, but this is not a frozen snapshot: changed sort/filter values may move rows. Legacy page-number parameters are ignored.

## Audit History

`mongoid-history` records whitelisted business fields for users, venues, programs, participant settings, and dated exceptions in `history_trackers`. Entries retain original/modified values, action, version, timestamps, and optional actor. Credentials, authentication challenges, pending email addresses, tokens, and session versions are excluded; photo bytes/metadata are outside this field audit.

Requests scope the actor through `Current`; anonymous/system writes have none unless explicitly wrapped in `Current.set(user: actor)`. History begins with new writes, without fabricated baselines. Normal callbacks create history; raw/atomic writes bypass it. Audit-sensitive activation and email changes use transactional saves with fresh predicates on retries.

System-admin-only `/admin/history` is read-only with `no-store`. It displays UTC timestamps, linked actors/subjects, actions, and escaped before/after values using indexed cursor pages and batched retrieval. Missing records retain readable names/IDs without broken links; nil actors are System / Anonymous.

Subject resolution allows only the five currently audited classes and supported root associations. `tracked_changes` applies current field policy before rendering. Unknown/retired classes retain metadata without exposing raw payloads or resolving arbitrary class names. The viewer adds no audit coverage or undo routes.

## Jobs and Google Calendar

Active Job uses `delayed_job_mongoid` in the same MongoDB replica set; no SQL or Redis is required. One shared worker handles calendar, mailers, and maintenance queues. Recurring schedules use transactional duplicate protection; jobs are idempotent with ID-only arguments, current-state authorization, and retained failures. See [Background Jobs](docs/background-jobs.md) for commands, retries, and recovery.

`EmailDelivery` stores encrypted tokens and source IDs, not contact snapshots. Account challenges and required workflow notifications enqueue in their transaction. Providers run outside transactions. Workers recheck expiry, current account/address, source state, permissions, and recipients. Queued is not delivered: SMTP acknowledgment crashes can duplicate messages, and in-flight mail cannot be recalled.

Optional Google OAuth connects one private calendar per program. Encrypted refresh tokens and expiring single-use OAuth state remain scoped to the current authorized manager. Only booked dates are mirrored; Google never mutates Posebook bookings. Disconnect removes credentials, not external events.

A separate transactional calendar outbox coalesces booking replacement chains, uses deterministic event IDs and leases, and retries provider failures. Shared-worker jobs drain changes and reconcile upcoming bookings every five minutes, skipping unchanged payloads. Rescheduling/reassignment updates the original event; cancellation cancels it. Calendar setup and verification live in [Google Calendar Setup](docs/google-calendar.md).

Each booking creates a shared meeting with participant and organizer emails visible to its invitees, not publicly. Guest edits/invitations and default reminders are disabled. The event includes venue/address/Maps information and effective program identity preferences. Optional lead minutes shift only the Google start; saved booking times, event end, attendance, and completion stay unchanged. Missing ends use one hour after the actual session start.

Read-only RSVP jobs poll every 12 hours. Responses stay tied to the current booking/calendar/payload; missing events clear them and provider failures retain the previous successful snapshot. Google acceptance does not confirm Posebook attendance, and decline does not cancel a booking.

## Architecture and Deployment

Rails 8.1 server-rendered views, Ruby 4.0, Mongoid 9.1, and MongoDB 8.0 form the runtime. MongoDB replica-set transactions and public framework/provider APIs are required. `Gemfile.lock` is committed because this is an application.

Read-side batching and cached values are request-local. Authentication remembers both a resolved account and an absent account only within the current request; every new request rechecks credentials. Date rendering reuses localized civil-date strings by locale, date, and format without caching timestamp clocks or relative-day decisions. Calendar overviews share their displayed booking snapshot with the next-session card, and booking dashboards batch eligible Google Calendar connection reads while retaining current viewer and connection-authority checks.

The production Docker image precompiles assets without live services, creates indexes at startup, and runs Puma as a non-root user. `/up` checks application liveness, not database readiness. Packaging verifies the actual image against isolated MongoDB, including transaction rollback and first-user registration. Development, CI, operations, and deployment settings are documented in [Contributing](CONTRIBUTING.md) and [Operating Posebook](docs/operating.md).

Production requires deployment-provided `MONGODB_URI`, `SECRET_KEY_BASE`, and an external `APP_HOST`. Web and worker share version, encryption secret, and provider settings. Filter contacts and authentication data from logs. Optional New Relic monitoring keeps exception messages, request attributes, and filtered application logs for diagnosing errors, but excludes request parameters, MongoDB queries, and browser injection; handled failures are reported without changing application outcomes.

## Theme and Artwork

The locally stored, MIT-licensed daisyUI Caramellatte theme supplies light cream/brown surfaces and sanguine controls without a runtime CDN, external fonts, or a Node/Tailwind build. Calendar colors retain their availability meaning. The portrait is decorative beside the wordmark; image galleries and wide tables scroll within accessible regions.

The MIT-licensed portrait was AI-generated and supplied by @dblock. Preserve `artwork/posebook-logo-source.png` unchanged outside the public asset pipeline; it is raster artwork, not editable vector paths. Its checkerboard pixels are removed by extracting red-versus-blue ink into alpha. Regenerate with ImageMagick:

```sh
magick artwork/posebook-logo-source.png -channel A -fx 'a*max(0,min(1,(r-b-0.008)/0.42))' +channel -channel RGB -fill '#a34c33' -colorize 100 +channel -resize 256x256 -strip app/assets/images/posebook-logo.png
magick app/assets/images/posebook-logo.png -resize 64x64 -gravity center -background none -extent 64x64 -strip app/assets/images/posebook-favicon.png
```

Inspect the portrait, rendered header, and favicon at 16/32 pixels after artwork changes.
