# Posebook

[![Test](https://github.com/dblock/posebook/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/posebook/actions/workflows/test.yml) [![Lint](https://github.com/dblock/posebook/actions/workflows/lint.yml/badge.svg)](https://github.com/dblock/posebook/actions/workflows/lint.yml) [![Package](https://github.com/dblock/posebook/actions/workflows/package.yml/badge.svg)](https://github.com/dblock/posebook/actions/workflows/package.yml) [![Coverage](https://coveralls.io/repos/github/dblock/posebook/badge.svg?branch=master)](https://coveralls.io/github/dblock/posebook?branch=master)

Invitation-first model registration, scheduling, and reminders for figure drawing venues.

## Installation

Requires Ruby 4.0.9 or newer within 4.0, Bundler, and MongoDB 8.0. The Docker packaging check also requires Docker.

```sh
git clone https://github.com/dblock/posebook.git
cd posebook
bin/setup --skip-server
```

## Usage

```sh
bin/dev
```

Open [localhost:3000](http://localhost:3000) and create the first user with a name, email, and password of at least 12 characters. That user receives the global `system_admin` role. Public registration then closes; later accounts require personal venue invitations. Sign in with email/password and use "Forgot your password?" for email recovery. Passwordless access and phone recovery are deferred.

Development reset emails are written to `tmp/mail/`. Reset links expire after 30 minutes, can be used once, and invalidate existing sessions when used. Automated model reminders are not implemented yet. `/up` checks application liveness, not database readiness.

Open **Profile** to view your account information. **Edit Profile**, **Change Password**, and **Deactivate Account** each have their own page, with a cancel link back to the profile. Successful profile and password edits return to the read-only profile with a confirmation message. Deactivation signs you out and confirms the result on the sign-in page.

Edit your name and optional international-format phone number from **Edit Profile**. Changing email requires your current password and confirmation at the new address; the old email remains your login and recovery address until confirmed, with the pending address shown on your profile. Phone numbers are stored but are not verified or used for recovery or messaging. Password changes retain the current browser session and revoke other sessions and outstanding recovery or email-change links.

Set an optional **Display name** for public calendars and announcements; leaving it blank uses your account name publicly instead. Add an optional Instagram profile link or @username during registration or from **Edit Profile**. Instagram stays private unless you explicitly allow public tagging, which makes the username and profile link public on venue calendars and in announcements. You can turn permission off at any time. Admins may edit display names and Instagram links but cannot opt users into tagging; changing an account's Instagram link as an admin revokes its previous consent. No public model directory or announcement sender exists.

Choose **Keep all my information private** during registration or from **Edit Profile** to hide your entire public identity at every venue. Calendars show **To be announced** instead of your name or Instagram, even if public tagging was previously allowed. Public sharing controls are disabled and dimmed while private. Saved preferences are retained and apply again when you turn privacy off. Only you can change this choice; authorized organizers still see the account name and private booking details they need.

Non-admin users can deactivate their accounts with their current password; history is retained. System admins can deactivate or reactivate users from **Users**. System admin accounts cannot be deactivated until role transfer is available, so administrator access cannot be lost. Deactivation revokes sessions and recovery links and prevents login and recovery. Public registration stays closed even when accounts are inactive.

System admins can use **Users > Edit** to change an existing user's name, email, and phone, including inactive accounts. Saves return to the user list with confirmation; invalid edits stay on the form. Email changes apply immediately without sending verification email, clear prior email verification, and revoke the user's sessions and outstanding recovery/email-change links. Changing your own email signs you out with confirmation. Roles, passwords, and account status are not editable through this form.

Use **Venues** to create a venue as a system admin, configure its address, IANA time zone, informational model pay in USD, instructions, and booking horizon, then grant `manage_schedule` to existing active users. Defaults are `America/New_York`, $140, and six months; each venue can have different settings. Organizers see only their assigned venues and cannot edit venue settings, manage other users, or assign organizers. System admins can manage all venues.

Removing schedule access preserves the membership record and immediately removes access to that venue. Deactivated users retain their assignments and bookings but cannot sign in until reactivated. Only system admins see organizer contact details and the existing-user selector, on the **Organizers** page linked beside **Edit Venue**. Automated model reminders remain future work.

Venues use `mongoid-slug` for readable URLs such as `/venues/enochs` and the shortcut `/enochs`. Slugs default to the venue name; admins can enter a **Slug** in venue settings or leave it blank to follow the name. Custom values are normalized, and duplicate/reserved values receive a numeric suffix. Previous slugs and existing `/venues/<database-id>` links keep working.

Venue pages are public: anyone with the link can see the name, address, regular schedule, and upcoming posing calendar. Booked active models show their public display name (or account name when blank) and Instagram only with public-tagging consent, unless they choose complete identity privacy and appear as **To be announced** instead. Inactive accounts retain their reserved slots without publishing identity. Contacts, canceled bookings/history, pay, model instructions, invitations, pause notes, and internal schedule explanations stay private. Venue lists remain signed-in and assignment-scoped; booking and management still require the appropriate membership. Month navigation refreshes the whole page if the viewer's login or access changes, removing stale private content.

Venue settings include one or more available weekdays, defaulting to Monday, and an editable regular start time, defaulting to 6:30 PM. The venue's month calendar shows drawing times and availability in its time zone through its configured booking horizon, with past dates, unavailable weekdays, occupied dates, and dates outside the window explicitly blocked. Models can book one available day per venue at a time; while scheduled, use **Change Date** or **Cancel Booking** instead of making a second reservation.

Admins and assigned venue organizers can use **Manage Schedule** or a calendar's **Edit Day** link to open an extra date/time, close a date for a holiday, change just one start time, or restore that date's regular weekday schedule. Every exception requires an explanation of up to 200 characters. Closing an occupied date cancels its booking with the explanation retained; changing its time keeps the model booked and records the old/new times and actor. Changing the regular venue time moves upcoming bookings without dated time overrides. No automatic notifications are sent.

Changing or canceling a model booking requires an explanation. Rescheduling retains the old date and reason and creates a linked new booking; cancellation retains the booking and frees the day. Booking another date creates another record, never overwriting or deleting prior bookings. Models see their own history; assigned organizers and system admins see venue history. Weekday/time-zone setting edits still preserve existing reservations. Start times are stored in UTC with venue-local display; session end times are not configured, so bookings continue to expire at the end of their saved local day. Automated reminders are future work.

Admins and assigned schedule organizers can **Invite a Model** at their venue. Create a single-use personal link to copy into email or a direct message, with optional SMTP delivery. The private link is displayed once, expires after 30 days, and can be revoked without deleting its record. Recipients can register or sign in with any existing account, then explicitly accept. They receive only venue-local model access, never organizer or global roles; models cannot see invitation/contact lists. Acceptance persists account creation, link consumption, and membership together in a MongoDB transaction.

Booking permission is separate from ongoing venue membership. Joining a venue as a model grants the first booking cycle. Cancellation or rescheduling keeps that permission, but completing a drawing does not permit another booking automatically. Admins and assigned organizers use **Models > Invite to Book** to enable the next cycle and send an email linking to the venue calendar. **Invite All Available Models** does this for active models who are not paused and have no upcoming booking at that venue. Invitations open booking immediately, not at a scheduled future release time. Drawings that have already started cannot be newly booked.

Use **Pause Model** with a short explanation to block booking/rescheduling at that venue without deactivating the account or canceling an existing booking. A paused model can still cancel. **Resume Model** preserves any unused permission but does not issue another invitation after a completed drawing. Pause explanations remain visible only to venue managers, with changes retained in audit history. Email failure is reported honestly while leaving booking enabled for direct follow-up; retrying an invitation is explicit. No automated repeat invitations or reminder scheduler is introduced.

User details/access and venue settings are audited with `mongoid-history`, storing previous/new values, action, time, and the signed-in actor in `history_trackers`. Passwords, authentication tokens/challenges, and session secrets are excluded. History starts with new writes after deployment; there is no history page or undo interface yet. Anonymous/system changes have no actor.

MongoDB must be a replica set (including a single-node development/test replica set) for invitation, booking, email-confirmation, and account activation transactions. DigitalOcean managed replica sets are supported; retain the provider's connection options. For local setup, follow the replica-set commands in [Contributing](CONTRIBUTING.md). Do not use `directConnection=true` with the Ruby driver.

## Configuration

| Variable           | Default                                                         | Purpose                                                                                          |
| ---                | ---                                                             | ---                                                                                              |
| `MONGODB_URI`      | `mongodb://127.0.0.1:27017/posebook_development` in development | MongoDB connection; required in production.                                                      |
| `MONGODB_TEST_URI` | `mongodb://127.0.0.1:27017/posebook_test`                       | Isolated test connection; database names must be `posebook_test` or start with `posebook_test_`. |
| `APP_HOST`         | `enochs.dblock.org`                                             | Production hostname allowed by Rails and used in account email links.                            |
| `SECRET_KEY_BASE`  | Rails development default                                       | Required production secret, supplied through deployment settings.                                |
| `PORT`             | `3000`                                                          | HTTP listen port behind an HTTPS-terminating proxy.                                              |

Export environment variables in your shell or configure them through DigitalOcean. `.env.example` documents local examples; Rails does not load `.env` files automatically. Production password recovery requires `SMTP_ADDRESS` and `MAIL_FROM`. Optional SMTP settings are `SMTP_PORT` (587), `SMTP_USERNAME`, and `SMTP_PASSWORD`; STARTTLS is enabled automatically. Without email configuration, registration/login work but password recovery explicitly reports that email is unavailable. SMS is not implemented.

For DigitalOcean App Platform, use the Dockerfile, HTTP port 3000, and `/up` as the health-check path. Store `MONGODB_URI`, `SECRET_KEY_BASE`, and `SMTP_PASSWORD` as encrypted settings; generate the session secret with `bundle exec rails secret`. Set `APP_HOST` to the hostname without a scheme. The production database name comes from the URI; use `posebook` while retaining the provider's authentication and TLS options. The Dockerfile already sets `RAILS_ENV=production` and `PORT=3000`. SMTP configuration also enables email-change confirmation; no email provider or infrastructure is provisioned by this repository.

`bin/setup` and the production Docker entry point create declared MongoDB indexes. The production entry point also runs `mongoid_slug:set[Venue]` before serving requests to generate missing slugs for existing venues without changing their IDs or existing slugs. Run `bundle exec rails 'mongoid_slug:set[Venue]'` manually for existing local data. Configure the database user to permit index creation and venue updates.

## Contributing

Read [Contributing](CONTRIBUTING.md), [Design](DESIGN.md), [Changelog](CHANGELOG.md), [Releasing](RELEASING.md), and [Working on Posebook](AGENTS.md).

## License

[MIT License](LICENSE.txt).
