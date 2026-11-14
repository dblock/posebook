# Design

## Purpose and Current Status

Posebook coordinates invitation-first model registration, scheduling, and reminders across figure drawing venues. The first venue is Figure Drawing at Enoch's, intended for `enochs.dblock.org`. The repository and application are named Posebook, not after a single venue.

The application currently provides first-user registration, role-bearing user accounts, email/password login, email password recovery, a protected home page, and a Rails `/up` liveness endpoint. `/up` proves application boot, not MongoDB connectivity. Model invitations, venue scheduling, bookings, and durable reminders are not implemented yet.

## Accounts and Recovery

There is one `User` model, not a separate admin account type. A blank installation allows anyone to register the first user without an installation secret, as explicitly requested. That account receives `system_admin` in its global roles. Public registration closes once any user exists; subsequent accounts must come through a future invitation flow. A fixed bootstrap document ID uses MongoDB's built-in unique `_id` constraint to prevent two concurrent first-user claims, without requiring a transaction or replica set.

Use email/password authentication initially, with BCrypt password hashing, a 12-character minimum, and the library's 72-byte maximum. Passwordless access is deferred. Public forms never accept role assignment. Sessions use encrypted, HTTP-only, same-site cookies, rotate on login/logout, expire after seven days, and include a per-user session version.

Email recovery links use random tokens, store only their SHA-256 digests, expire after 30 minutes, and are consumed atomically with the password update. Resetting rotates the session version, invalidating every existing session. A newer reset request supersedes older links. Requests use the same success message for known and unknown emails. Login, signup, and reset requests use Rails rate limits backed by the application's cache; these limits are per process with the current memory cache, not distributed across instances.

Development emails are written to `tmp/mail`; tests use the in-memory mail adapter. Production recovery uses configurable SMTP, requires `SMTP_ADDRESS` and `MAIL_FROM`, and reports unavailable delivery rather than pretending to send email. Reset URLs use configured mailer hosts, not incoming request hosts. Phone recovery, email changes/verification, and account invitations remain future work.

## Agreed Model Workflow

An organizer first connects with a model by email, Instagram, or text. The organizer adds them to the appropriate venue, possibly with only a name or social handle, then sends a private registration link by email or through the existing conversation.

The planned model invitation flow collects name, email, and phone number, verifies contact information, and obtains explicit consent for automated SMS. Initial accounts use passwords; passwordless access can follow later. Declining SMS must not prevent email-based registration or booking.

After registering, the model chooses an available session at the inviting venue. The invitation has no preselected date; the selection immediately confirms the booking. Send confirmation by email and, with consent, SMS, plus a calendar invitation. Models can cancel or reschedule and organizers are notified.

One week before posing, send email and consented SMS reminders with a confirmation link. Organizers can see acknowledgments, delivery failures, and upcoming sessions. Bookings made within the reminder window receive their booking confirmation immediately, not a redundant overdue reminder.

## Venue Boundaries and Scheduling

A model has one identity and separate venue memberships. Organizers see only memberships and booking history for venues they manage. Contacts and model rosters are private by default. Visiting a venue hostname shows only that venue; hostname routing must never substitute for authorization.

Each venue owns its invitations, roster, recurring schedule, time zone, address, pay, instructions, and configurable booking horizon. Default availability is the next six months, opened automatically. Enoch's initially meets Mondays around 6:30-9:00 PM in `America/New_York`; individual dates can be blocked or overridden.

A model may have one upcoming booking per venue, while retaining historical bookings. Database constraints and atomic mutations must prevent concurrent claims of one session or multiple upcoming bookings at one venue. A partial unique index on an explicit active-booking state can enforce active claims, but time passing does not update indexes: completion transitions must release claims, and the final design must test rollover and recovery. Do not rely on uniqueness validations alone.

Calculate weekly sessions and the one-week reminder in the venue's local calendar, then store instants in UTC. Cover daylight saving changes. Cancellation and rescheduling must invalidate obsolete pending messages and update calendar invitations. Reminder delivery requires a durable worker, idempotent scheduling, retries, opt-out handling, and acknowledgment tracking; a successful provider request is not proof of recipient delivery.

## Architecture and Deployment

Use Rails 8.1 with server-rendered views, Mongoid 9.1, and MongoDB 8.0. Ruby 4.0.9 is the stable runtime selected at scaffold creation. Test one MongoDB version, 8.0, to match the deployment target rather than maintaining a server-version compatibility matrix. Commit `Gemfile.lock` because this is an application, not a published gem.

Use Rails and Mongoid public APIs. Do not configure Active Record, Solid Queue, or another SQL-backed component. The scaffold retains ActiveJob's in-process adapter solely as framework setup; a durable MongoDB-compatible worker and notification providers will be selected and tested in the implementation phase. No background reminders are promised by this scaffold.

The Dockerfile explicitly selects runtime files, installs production dependencies, precompiles assets without live services, creates declared indexes at container startup, and runs Puma as a non-root user. The package check runs the built image against its own MongoDB 8.0 container and verifies first-user registration, compiled CSS, and liveness. Application tests exercise real MongoDB persistence and concurrent first-user/reset claims. Deployment is intended for DigitalOcean App Platform with managed MongoDB and an HTTPS-terminating proxy, but no infrastructure or credentials are provisioned.

Production requires `MONGODB_URI` and a deployment-supplied `SECRET_KEY_BASE`. `APP_HOST` defaults to `enochs.dblock.org`; production requests are host-restricted except for `/up`. Local test configuration uses a separate URI and a test-only database-name guard. Filter email, phone, passwords, and authentication tokens from logs. Email password recovery uses SMTP; model notifications remain unimplemented.

## Delivery Scope

Implementation proceeds through focused stacked PRs: account bootstrap and recovery, venue/organizer setup, recurring sessions, invitations, then bookings and email/SMS reminders. SMS consent, phone verification, opt-outs, invitation expiry, and adult-model expectations are required before the corresponding public functionality launches.

Version one excludes payments, artist registration, public model directories, and photo uploads. No logo or other artwork has been selected or created.
