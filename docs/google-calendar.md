# Google Calendar Setup

Posebook uses Google's official [`google-apis-calendar_v3`](https://github.com/googleapis/google-api-ruby-client) Ruby client. Synchronization is optional and configured per program. Booking data flows from Posebook to Google; Google invitation responses are read separately. Only booked slots become Google events, not unbooked days. Booking, rescheduling, organizer replacements, schedule time changes, and cancellations are synchronized. Google edits and responses never change Posebook bookings or attendance confirmation.

## Configure Google OAuth

1. Create a project in [Google Cloud Console](https://console.cloud.google.com/) and enable the **Google Calendar API**.
2. Configure the Google Auth Platform consent screen. Use **Internal** if all authorizing organizers belong to your Google Workspace organization; otherwise use **External** and add your organizer Google accounts as test users during setup.
3. Create an OAuth client of type **Web application**. Add the exact authorized redirect URI `https://YOUR_POSEBOOK_HOST/google_calendar/callback`. For local development, also add `http://localhost:3000/google_calendar/callback`.
4. Set `GOOGLE_CALENDAR_CLIENT_ID`, `GOOGLE_CALENDAR_CLIENT_SECRET`, and `GOOGLE_CALENDAR_REDIRECT_URI` on the application and worker. Store the secret in encrypted deployment settings, never Git or a PR. The configured redirect URI must match the Google client exactly. Keep `APP_HOST` set to the production hostname for event links.

Posebook requests `calendar.events` to manage events and `calendar.calendarlist.readonly` to verify the selected calendar and write access. OAuth is needed for attendee invitations; an ordinary service account cannot populate attendee lists without Workspace domain-wide delegation. Use a Google account that can edit the chosen calendar.

External OAuth apps in **Testing** generally receive refresh tokens that expire after seven days for these scopes. Before relying on production sync, publish the consent screen and complete any Google-required verification. See Google's [OAuth production readiness guidance](https://developers.google.com/identity/protocols/oauth2/production-readiness/policy-compliance). Token revocation or expiry requires reconnecting in Posebook.

## Start the Worker

Run the shared background worker using the same application image, MongoDB replica set, OAuth settings, and `SECRET_KEY_BASE` as the web component:

```sh
bundle exec rake jobs:work
```

On DigitalOcean App Platform, add a **Worker** component using the application Dockerfile and that run command. The same worker handles calendar jobs and future Active Jobs; no separate calendar worker is required. Keep it running with automatic restarts. Do not run it inside the web process. `SECRET_KEY_BASE` encrypts stored refresh tokens; changing it without migrating the tokens requires reconnecting every calendar. See [Background Jobs](background-jobs.md) for queue filtering, scheduled runs, retries, and monitoring.

For a bounded manual run:

```sh
bundle exec rake google_calendar:sync
```

This reconciles upcoming bookings and processes at most 100 due changes. The shared worker runs recurring reconciliation every five minutes and calendar delivery batches every five seconds, subject to queue capacity and idle polling. MongoDB persists changes inside the booking transaction; no Google call runs before commit. Failures retry with capped exponential backoff, and an expired lease recovers work after a worker restart. Only safe error classifications are stored, never provider response text or tokens. The calendar-specific outbox retains provider state; the generic Active Job queue schedules its processing.

## Connect a Program

1. Create a dedicated calendar in Google Calendar. Keep it private and share it only with authorized program organizers.
2. Under the calendar's **Settings and sharing**, copy the **Calendar ID** from **Integrate calendar**.
3. In Posebook, select the program's **Google Calendar** tab, enter the ID, confirm restricted access, and authorize the Google account. Upcoming bookings are queued automatically.
4. Make a synthetic booking with an email account you control, verify the invitation and event, reschedule it, then cancel it. Confirm that Google moves the same event and sends the cancellation.

Events include the model's name, public name, email, unverified phone, gender, private-identity choice, and effective Instagram tagging permission. A permitted Instagram handle is included; disabled tagging or private identity omits it. Events invite the model, assigned program and venue organizers, and the connecting organizer. They are marked private, disallow guest edits/invitations, hide the guest list, and disable default reminders. Calendar permissions still determine who can read details; do not rely on the event's private flag to protect an improperly shared calendar.

Google invitations are explicitly requested transactional booking notifications. Recipients' Google Calendar settings can require accepting an invitation before it appears in their personal calendar. No SMS, automated reminder campaign, or account directory is introduced.

The event uses saved booking times and the program's time zone. In program **Edit**, set **Calendar invitation lead time (minutes)** to a whole number of 0 or greater, defaulting to 0. With 15 minutes configured, a 10:00 session's Google invitation starts at 9:45; its description states the actual session start. The session's stored times, calendar, attendance deadlines, and booking history do not move. Google event end times stay unchanged; without a session end time, the fallback remains one hour after the actual session start, not the earlier invitation start. Changing the lead time queues updates for all upcoming bookings, including dated time exceptions. Rescheduling preserves the original Google event ID, including organizer participant replacements. Periodic reconciliation updates current contact/tagging information without sending unchanged events again.

## Monitor and Disconnect

Every 12 hours, the shared worker schedules a separate response check for each synchronized upcoming booking. Organizers see a one-word Google RSVP label beside the booking status in calendars, history, and booking editing: Pending, Accepted, Tentative, or Declined. Pending means Google reports that the model has not responded. The label's tooltip shows the last successful check in the session's time zone. Models, unrelated users, and public visitors do not see these labels.

Google RSVP is independent of Posebook attendance confirmation: accepting does not confirm attendance, and declining does not cancel a reservation. Checks match the model's email, not an organizer's response. Old responses are hidden after the booking or synchronized payload changes, and disabled or unauthorized connections are not checked. Missing events or attendees clear the response rather than being treated as declines. Provider failures retry through the shared queue and retain the last successful response and its timestamp; responses are not real-time.

The program's Google Calendar page shows the count of changes awaiting synchronization. Reconnect when authorization fails; confirm the worker is running if that count does not drain. A revoked or inactive connecting organizer cannot continue synchronizing private data; an authorized organizer must reconnect.

Disconnecting stops synchronization and clears the stored credential, but leaves previously created Google events and invitations intact. Remove old events manually before changing the destination calendar. Do not manually delete or edit Posebook-managed events: subsequent updates may overwrite edits, and a deleted event may require manual recovery. No production connection or real invitations are sent by automated tests.
