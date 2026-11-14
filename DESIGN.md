# Design

## Purpose and Current Status

Posebook coordinates invitation-first model registration, scheduling, and reminders across figure drawing venues. The first venue is Figure Drawing at Enoch's, intended for `enochs.dblock.org`. The repository and application are named Posebook, not after a single venue.

The application currently provides first-user registration, role-bearing user accounts, email/password login, email password recovery, account settings, deactivation/reactivation, venue configuration, scoped organizer access, a protected home page, and a Rails `/up` liveness endpoint. `/up` proves application boot, not MongoDB connectivity. Model invitations, venue scheduling, bookings, and durable reminders are not implemented yet.

## Accounts and Recovery

There is one `User` model, not a separate admin account type. A blank installation allows anyone to register the first user without an installation secret, as explicitly requested. That account receives `system_admin` in its global roles. Public registration closes once any user exists; subsequent accounts must come through a future invitation flow. A fixed bootstrap document ID uses MongoDB's built-in unique `_id` constraint to prevent two concurrent first-user claims, without requiring a transaction or replica set.

Use email/password authentication initially, with BCrypt password hashing, a 12-character minimum, and the library's 72-byte maximum. Passwordless access is deferred. Public forms never accept role assignment. Sessions use encrypted, HTTP-only, same-site cookies, rotate on login/logout, expire after seven days, and include a per-user session version.

Email recovery links use random tokens, store only their SHA-256 digests, expire after 30 minutes, and are consumed atomically with the password update. Resetting rotates the session version, invalidating every existing session. A newer reset request supersedes older links. Requests use the same success message for known and unknown emails. Login, signup, and reset requests use Rails rate limits backed by the application's cache; these limits are per process with the current memory cache, not distributed across instances.

Account settings allow name and optional international-format phone changes. Phone numbers are unverified and cannot be used for recovery or messaging yet. Email changes require the current password and a single-use, 30-minute verification link at the new address. GET displays confirmation without changing the address; an atomic PATCH consumes the token, changes email under its unique index, invalidates all sessions, and clears authentication challenges. Until then, login and recovery use the old email. Authenticated password changes require the current password, rotate session versions, retain the current browser, and invalidate other sessions and outstanding challenges.

The profile is a read-only account summary with links to separate profile-edit, password-change, and account-deactivation pages. Successful profile/password edits redirect back to the summary with a confirmation; invalid submissions stay on their corresponding form. Every form has a cancel link to the summary. Successful deactivation signs out the user and confirms the result on the sign-in page rather than returning to an authenticated page.

Deactivation retains the user and history while revoking sessions, email-change links, and recovery links. Inactive users cannot log in or request recovery; old documents without an active flag remain active. Only system admins can manage other users or reactivate accounts. System admin accounts cannot be deactivated until global role transfer exists: protecting these accounts atomically avoids concurrent last-admin races. Public registration remains closed even if all non-admin accounts are inactive.

Development emails are written to `tmp/mail`; tests use the in-memory mail adapter. Production account email uses configurable SMTP, requires `SMTP_ADDRESS` and `MAIL_FROM`, and reports unavailable delivery rather than pretending to send email. Links use configured mailer hosts, not incoming request hosts. Phone recovery and account invitations remain future work.

System admins can edit any existing user's name, email, and phone, including inactive accounts, without changing roles, passwords, or active status. Successful edits return to the user list with confirmation; invalid edits stay on the form. Admin email changes apply immediately without verification or the target user's password, clear previous verification, revoke all sessions and outstanding authentication challenges, and handle competing unique email claims. Name/phone-only edits preserve sessions and pending email changes. An admin changing their own email is signed out with confirmation and must sign in again. Account access still has separate explicit controls; missing edits or invalid access values never default to deactivation.

## Agreed Model Workflow

An organizer first connects with a model by email, Instagram, or text. The organizer adds them to the appropriate venue, possibly with only a name or social handle, then sends a private registration link by email or through the existing conversation.

The planned model invitation flow collects name, email, and phone number, verifies contact information, and obtains explicit consent for automated SMS. Initial accounts use passwords; passwordless access can follow later. Declining SMS must not prevent email-based registration or booking.

After registering, the model chooses an available session at the inviting venue. The invitation has no preselected date; the selection immediately confirms the booking. Send confirmation by email and, with consent, SMS, plus a calendar invitation. Models can cancel or reschedule and organizers are notified.

One week before posing, send email and consented SMS reminders with a confirmation link. Organizers can see acknowledgments, delivery failures, and upcoming sessions. Bookings made within the reminder window receive their booking confirmation immediately, not a redundant overdue reminder.

## Venue Boundaries and Scheduling

A model has one identity and separate venue memberships. Organizers see only memberships and booking history for venues they manage. Contacts and model rosters are private by default. Visiting a venue hostname shows only that venue; hostname routing must never substitute for authorization.

Venue configuration and organizer access are implemented. Only global system admins can create/edit venues or grant/revoke organizer access. A `VenueMembership` links an existing user and venue with local roles; `manage_schedule` never changes the user's global roles. A compound unique index on venue/user plus an atomic upsert and set addition prevents duplicate memberships or roles under concurrent grants. Revocation atomically pulls just that role and preserves the membership for future history. Deactivation blocks the user's access without deleting assignments.

Organizers can list/view only assigned venues; unassigned venue lookups return 404. Schedule access does not permit venue configuration, user administration, or role assignment. Only system admins see organizer emails and the active-user assignment selector. Invitations are deferred, so this interface assigns existing users only. Venue hostname routing, model rosters, and schedule editing remain future work.

Each venue currently stores name, address, IANA time zone, decimal model pay in USD, instructions, and a positive booking horizon in months. Defaults match the initial Enoch's venue: `America/New_York`, $140, and six months. Pay is informational, not payment processing. Validated time-zone identifiers prepare for calendar-aware scheduling; recurring dates and reminder calculations are not implemented here.

Each venue owns its invitations, roster, recurring schedule, time zone, address, pay, instructions, and configurable booking horizon. Default availability is the next six months, opened automatically. Enoch's initially meets Mondays around 6:30-9:00 PM in `America/New_York`; individual dates can be blocked or overridden.

A model may have one upcoming booking per venue, while retaining historical bookings. Database constraints and atomic mutations must prevent concurrent claims of one session or multiple upcoming bookings at one venue. A partial unique index on an explicit active-booking state can enforce active claims, but time passing does not update indexes: completion transitions must release claims, and the final design must test rollover and recovery. Do not rely on uniqueness validations alone.

Calculate weekly sessions and the one-week reminder in the venue's local calendar, then store instants in UTC. Cover daylight saving changes. Cancellation and rescheduling must invalidate obsolete pending messages and update calendar invitations. Reminder delivery requires a durable worker, idempotent scheduling, retries, opt-out handling, and acknowledgment tracking; a successful provider request is not proof of recipient delivery.

## Architecture and Deployment

Use Rails 8.1 with server-rendered views, Mongoid 9.1, and MongoDB 8.0. Ruby 4.0.9 is the stable runtime selected at scaffold creation. Test one MongoDB version, 8.0, to match the deployment target rather than maintaining a server-version compatibility matrix. Commit `Gemfile.lock` because this is an application, not a published gem.

Use Rails and Mongoid public APIs. Do not configure Active Record, Solid Queue, or another SQL-backed component. The scaffold retains ActiveJob's in-process adapter solely as framework setup; a durable MongoDB-compatible worker and notification providers will be selected and tested in the implementation phase. No background reminders are promised by this scaffold.

The Dockerfile explicitly selects runtime files, installs production dependencies, precompiles assets without live services, creates declared indexes at container startup, and runs Puma as a non-root user. The package check runs the built image against its own MongoDB 8.0 container and verifies first-user registration, compiled CSS, and liveness. Application tests exercise real MongoDB persistence and concurrent bootstrap, reset, email-confirmation, and organizer-assignment claims. Deployment is intended for DigitalOcean App Platform with managed MongoDB and an HTTPS-terminating proxy, but no infrastructure or credentials are provisioned.

Production requires `MONGODB_URI` and a deployment-supplied `SECRET_KEY_BASE`. `APP_HOST` defaults to `enochs.dblock.org`; production requests are host-restricted except for `/up`. Local test configuration uses a separate URI and a test-only database-name guard. Filter email, phone, passwords, and authentication tokens from logs. Email password recovery uses SMTP; model notifications remain unimplemented.

## Delivery Scope

Implementation proceeds through focused stacked PRs: account bootstrap and recovery, account settings and lifecycle, venue/organizer setup, recurring sessions, invitations, then bookings and email/SMS reminders. SMS consent, phone verification, opt-outs, invitation expiry, and adult-model expectations are required before the corresponding public functionality launches.

Version one excludes payments, artist registration, public model directories, and photo uploads. No logo or other artwork has been selected or created.
