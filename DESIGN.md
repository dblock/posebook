# Design

## Purpose and Current Status

Posebook coordinates invitation-first model registration, scheduling, and reminders across figure drawing venues. The first venue is Figure Drawing at Enoch's, intended for `enochs.dblock.org`. The repository and application are named Posebook, not after a single venue.

The current scaffold provides a server-rendered placeholder page, a Rails `/up` liveness endpoint, Mongoid configuration, tests, linting, and production Docker packaging. `/up` proves application boot, not MongoDB connectivity. No invitations, registration, bookings, provider integrations, or durable reminders are implemented.

## Agreed Model Workflow

An organizer first connects with a model by email, Instagram, or text. The organizer adds them to the appropriate venue, possibly with only a name or social handle, then sends a private registration link by email or through the existing conversation.

The model registers with name, email, and phone number, verifies their contact information, and provides explicit consent for automated SMS. Returning access uses emailed sign-in links, never passwords. Declining SMS must not prevent email-based registration or booking.

After registering, the model chooses an available session at the inviting venue. The invitation has no preselected date; the selection immediately confirms the booking. Send confirmation by email and, with consent, SMS, plus a calendar invitation. Models can cancel or reschedule and organizers are notified.

One week before posing, send email and consented SMS reminders with a confirmation link. Organizers can see acknowledgments, delivery failures, and upcoming sessions. Bookings made within the reminder window receive their booking confirmation immediately, not a redundant overdue reminder.

## Venue Boundaries and Scheduling

A model has one identity and separate venue memberships. Organizers see only memberships and booking history for venues they manage. Contacts and model rosters are private by default. Visiting a venue hostname shows only that venue; hostname routing must never substitute for authorization.

Each venue owns its invitations, roster, recurring schedule, time zone, address, pay, instructions, and configurable booking horizon. Default availability is the next six months, opened automatically. Enoch's initially meets Mondays around 6:30-9:00 PM in `America/New_York`; individual dates can be blocked or overridden.

A model may have one upcoming booking per venue, while retaining historical bookings. Database constraints and atomic mutations must prevent concurrent claims of one session or multiple upcoming bookings at one venue. A partial unique index on an explicit active-booking state can enforce active claims, but time passing does not update indexes: completion transitions must release claims, and the final design must test rollover and recovery. Do not rely on uniqueness validations alone.

Calculate weekly sessions and the one-week reminder in the venue's local calendar, then store instants in UTC. Cover daylight saving changes. Cancellation and rescheduling must invalidate obsolete pending messages and update calendar invitations. Reminder delivery requires a durable worker, idempotent scheduling, retries, opt-out handling, and acknowledgment tracking; a successful provider request is not proof of recipient delivery.

## Architecture and Deployment

Use Rails 8.1 with server-rendered views, Mongoid 9.1, and MongoDB. Ruby 4.0.9 is the current stable runtime at scaffold creation. MongoDB 9.0 is current stable; test 8.0 as well for compatibility with existing deployments. Commit `Gemfile.lock` because this is an application, not a published gem.

Use Rails and Mongoid public APIs. Do not configure Active Record, Solid Queue, or another SQL-backed component. The scaffold retains ActiveJob's in-process adapter solely as framework setup; a durable MongoDB-compatible worker and notification providers will be selected and tested in the implementation phase. No background reminders are promised by this scaffold.

The Dockerfile explicitly selects runtime files, installs production dependencies, precompiles assets without live services, and runs Puma as a non-root user. The package check executes the built image and verifies actual HTTP responses and compiled CSS. Application tests separately exercise real MongoDB persistence. Deployment is intended for DigitalOcean App Platform with managed MongoDB and an HTTPS-terminating proxy, but no infrastructure or credentials are provisioned.

Production requires `MONGODB_URI` and a deployment-supplied `SECRET_KEY_BASE`. `APP_HOST` defaults to `enochs.dblock.org`; production requests are host-restricted except for `/up`. Local test configuration uses a separate URI and a test-only database-name guard. Filter email, phone, and authentication tokens from logs. Email delivery remains disabled until its implementation.

## Delivery Scope

The scaffold is reviewed before implementation. Implementation follows in focused PRs: venue/organizer setup and recurring sessions, invitations and registration, then bookings and email/SMS reminders. SMS consent, phone verification, opt-outs, expiring authentication links, rate limits, and adult-model expectations are required before the corresponding public functionality launches.

Version one excludes payments, artist registration, public model directories, and photo uploads. No logo or other artwork has been selected or created.
