# Upgrading

## Application Draft Maintenance

Deploy web and worker at the same version. The default shared worker handles the new `maintenance` queue automatically; installations filtering `JOB_QUEUES` must add it, for example `JOB_QUEUES=calendar,mailers,maintenance`, or deploy a dedicated maintenance worker. Completion reminders require the existing `mailers` worker and SMTP configuration. Startup creates the draft status/creation index; existing submitted applications need no migration and are never cleaned up as drafts. Maintenance runs hourly, so reminders and cleanup depend on worker and queue availability. See [Background Jobs](docs/background-jobs.md).

## Program URLs

Program URLs now use `/programs` instead of `/sessions`, including calendars, bookings, galleries, management, and Google Calendar settings. Creating a program uses `/venues/:venue_slug/programs/new` and posts to `/venues/:venue_slug/programs`. Update saved bookmarks, shared links, and external clients to the new prefix; old `/sessions` paths are not redirected or aliased. Authentication remains at `/session`, and the Google OAuth callback is unchanged. No database or slug migration is required.

## Queued Transactional Email

Account recovery, email-change verification, participant/coordinator invitations, and invitations to book again now require the shared background worker. Deploy web and worker together with the same version, SMTP settings, `MAIL_FROM`, `APP_HOST`, and `SECRET_KEY_BASE`. Remove a calendar-only queue filter, include `mailers` in `JOB_QUEUES=calendar,mailers`, or add a dedicated mail worker before serving the new web version. Startup creates the encrypted email outbox indexes; no data migration is required.

Requests now report email queued rather than sent. Existing token lifetimes are unchanged, including the 30-minute recovery/verification deadline measured from the request; monitor worker delays and failures. In development, email files appear only after the worker runs. See [Background Jobs](docs/background-jobs.md) for safe retries and at-least-once SMTP delivery.

## Instagram Tagging

First-user and invitation registration forms now select Instagram tagging by default and require a valid handle when selected. Users can clear the checkbox. Existing accounts and their saved preferences are unchanged; no migration is required. If a new user selects private identity and the browser omits the disabled public-sharing fields, tagging is off until explicitly enabled.

## Required Phone and Gender

Before serving this version, stop all application writers, back up MongoDB, and run `bundle exec rake users:backfill_required_details` using the new application image and the production `MONGODB_URI`. The command runs explicitly, not at startup. It fills only blank phone values with the fictional US number `+12025550100` and only blank gender values with `male`, including inactive accounts; existing values are preserved. Each changed account is saved with audit history in its own transaction. If a validation or database error stops the command, fix it and rerun; completed accounts are skipped. Do not start the new application until it succeeds.

These are placeholders, not verified contact details or confirmed genders. Ask affected users to update their profiles. The default gender can affect consecutive-gender booking rules; review affected bookings and scheduling decisions. New registrations and profile edits now require both fields; formatted phone input is normalized to international format. Phone verification and messaging remain unavailable.

## Generic Defaults

New programs default to **Program** and **Participant**, zero pay, Mondays at 09:00 UTC, and a six-month booking horizon. Existing stored labels, schedules, pay, memberships, and booking history are not rewritten. Configured gender rules and explicit organizer overrides remain supported.

`APP_HOST` now defaults to `localhost`. Set it to your actual hostname for an external deployment, particularly if the installation previously relied on the old built-in hostname. Authentication remains at `/session`. No data migration is required.

## Optional Invitation Email Restrictions

All invitation types now allow a blank recipient email, generating a private single-use link without sending email. When an email is specified, registration and existing-account acceptance must match it. This also applies to pending participant invitations created before this change: their optional delivery address now restricts acceptance. Revoke and reissue an invitation without email, or with the intended address, if its existing recipient address is unsuitable. Already-consumed invitations and memberships are unchanged; no token or database migration is required.

Wrong signed-in accounts must sign out and switch to the invited address; the invitation is preserved across logout/login. Direct acceptance clients now receive 403 for an existing-account email mismatch or 422 for a registration mismatch, rather than consuming participant invitations or reporting a coordinator link as expired. Blank-email coordinator creation clients may omit the `email` parameter.

## Coordinator Invitations

Coordinator pages accept new or registered email addresses. Existing-email promotion requires an explicit confirmation; direct email-based assignment clients must submit `grant_access=1` to confirm. Existing user-ID assignment remains supported. Coordinator invitations use a separate collection; see the optional email policy above. Normal startup creates its declared indexes; no data migration or changes to existing memberships are required.

## Retired One-Time Conversions

The sole instance must deploy [PR #52](https://github.com/dblock/posebook/pull/52) and finish its automatic conversion before deploying the migration-free application. That version supplies the schema rename, legacy venue split, Instagram handle conversion, and slug backfills. Stop older application versions before that conversion and verify the existing admin, venue, and program afterward. Do not deploy the current version directly against an older schema.

Current startup creates declared MongoDB indexes only. Historical conversion classes, rake tasks, tests, and schema flags are no longer shipped; there are no automatic collection/field/role conversions, Instagram data rewrites, or startup slug backfills. This removal does not delete stored accounts, venues, programs, photos, bookings, or audit history.

Normal saves still generate and retain venue/program slugs, and normal profile input still accepts Instagram handles or profile URLs. Public program pages use `/programs/:slug`, venues use `/venues/:slug`, and authentication uses `/session`.
