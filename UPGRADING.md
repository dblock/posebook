# Upgrading

## Coordinator Invitations

Coordinator pages now accept new or registered email addresses. Existing-email promotion requires an explicit confirmation; direct email-based assignment clients must submit `grant_access=1` to confirm. Existing user-ID assignment remains supported. New coordinator invitations use a separate collection and restrict acceptance to the invited email. Normal startup creates its declared indexes; no data migration or changes to existing memberships and participant invitations are required.

## Retired One-Time Conversions

The sole instance must deploy [PR #52](https://github.com/dblock/posebook/pull/52) and finish its automatic conversion before deploying the migration-free application. That version supplies the schema rename, legacy venue split, Instagram handle conversion, and slug backfills. Stop older application versions before that conversion and verify the existing admin, venue, and program afterward. Do not deploy the current version directly against an older schema.

Current startup creates declared MongoDB indexes only. Historical conversion classes, rake tasks, tests, and schema flags are no longer shipped; there are no automatic collection/field/role conversions, Instagram data rewrites, or startup slug backfills. This removal does not delete stored accounts, venues, programs, photos, bookings, or audit history.

Normal saves still generate and retain venue/program slugs, and normal profile input still accepts Instagram handles or profile URLs. Public program pages stay at `/sessions/:slug`, venues at `/venues/:slug`, and authentication at `/session`.
