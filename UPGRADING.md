# Upgrading

## Generic Programs, Participants, and Bookings

The production entry point automatically runs `programs:migrate_schema` before the existing venue conversion, index creation, slug backfill, and HTTP server startup. No manual migration or backup step is required for the sole instance. Stop the old application before starting the new version; the two schemas must not serve concurrently.

The conversion renames the drawing-session and model collections, updates program and booking references, converts membership roles and pause fields, renames `model_pay` to `pay`, and updates retained audit scopes and fields. Existing IDs, accounts, venues, slug history, booking state, and invitations are preserved. Programs default to the labels **Session** and **Model**. Configured labels survive repeat execution.

Conversion is safe to rerun, including after an interrupted startup. Conflicting old/new collections or fields stop startup rather than overwriting data; resolve the reported conflict and restart. The database account must be able to rename collections within its database and create/remove indexes. The startup migration will be removed in a subsequent change after the sole instance has deployed successfully.

Public program pages stay at `/sessions/:slug`, including retained slugs and ID lookup. Participant galleries and program participant, invitation, and booking routes use the new generic names; old model-specific paths are not retained. Login/logout stays at `/session`.

## Separating Venues and Recurring Sessions

Back up MongoDB before upgrading, including `history_trackers`, `venue_photos`, `photos.files`, and `photos.chunks`. Stop the old application version before migrating; old and new versions must not serve concurrently because the booking foreign keys and claim indexes change.

Run `bundle exec rails programs:migrate_schema venues:split_programs db:create_indexes 'mongoid_slug:set[Venue,Program]'` with the target `MONGODB_URI` and a MongoDB replica set. `bin/setup` and the production entry point run these steps before serving requests. The database user needs permission to rename collections and create/remove indexes.

Each legacy venue becomes a location plus one recurring `Program`. Both keep the original venue ID; the session keeps its name, slug history, schedule, time zone, pay, instructions, booking rules, and schedule revision. Venue photos and Instagram stay at the location. Bookings, claims, invitation tokens, model grants/pauses, and dated exceptions retain their IDs and saved state while becoming session-scoped. Legacy coordinators receive only session coordinator access, never venue coordinator access. Existing audit records remain; session-related venue history is also copied into session history, and membership history follows its migrated membership.

Conversion is transactional per venue and safe to rerun after interruption. Replacement session-scoped unique claim indexes are installed before removing legacy venue indexes. Do not start the new application until all migration and index steps pass. If migration fails, correct the reported problem and rerun, or restore the backup together with the old application version; do not run the old version against partially migrated data.

Calendar and booking URLs now use `/sessions/:slug`; `/venues/:slug` shows the location and its sessions. Old root shortcuts and venue-nested calendar/booking URLs are not redirected. Publish the new session links.

Admins assign venue coordinators. Venue coordinators edit their location and public photos, create/manage all its sessions, and assign session coordinators. Session coordinators edit and manage only their assigned sessions and cannot grant coordinator roles. Models need separate invitations for each session and may hold one upcoming booking per session. No new cross-session date or time conflict restriction is added.
