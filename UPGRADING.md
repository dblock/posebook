# Upgrading

## Retired One-Time Conversions

The sole instance must deploy [PR #52](https://github.com/dblock/posebook/pull/52) and finish its automatic conversion before deploying the migration-free application. That version supplies the schema rename, legacy venue split, Instagram handle conversion, and slug backfills. Stop older application versions before that conversion and verify the existing admin, venue, and program afterward. Do not deploy the current version directly against an older schema.

Current startup creates declared MongoDB indexes only. Historical conversion classes, rake tasks, tests, and schema flags are no longer shipped; there are no automatic collection/field/role conversions, Instagram data rewrites, or startup slug backfills. This removal does not delete stored accounts, venues, programs, photos, bookings, or audit history.

Normal saves still generate and retain venue/program slugs, and normal profile input still accepts Instagram handles or profile URLs. Public program pages stay at `/sessions/:slug`, venues at `/venues/:slug`, and authentication at `/session`.
