# Contributing

## Setup and Validation

Install Ruby 4.0.9, Bundler, MongoDB 8.0, and Docker. Use only MongoDB 8.0 for tests to match the deployment target. No production service credentials are required.

Use an existing local MongoDB server or start a dedicated development container on an unused port:

```sh
docker run --detach --name posebook-mongo --publish 127.0.0.1:27017:27017 mongo:8.0 --replSet rs0 --bind_ip_all
docker exec posebook-mongo mongosh --quiet --eval 'rs.initiate({_id:"rs0",members:[{_id:0,host:"127.0.0.1:27017"}]})'
bin/setup --skip-server
bundle exec rake spec
bundle exec rake lint
bundle exec rake package
```

Wait for a writable replica-set primary before setup. If port 27017 is occupied, use an existing replica set or run MongoDB on the same unused port inside and outside the container, advertise that address in the replica-set configuration, and export `MONGODB_URI` and `MONGODB_TEST_URI` with `?replicaSet=rs0`. Do not use `directConnection=true`: the Ruby driver treats it as standalone topology and refuses transactions. Do not overwrite another project's containers. Stop your development container with `docker stop posebook-mongo` when no longer needed.

Run tests and lint before every development push, including amendments. Run packaging validation before committing packaging, runtime dependency, configuration, or HTTP entry-point changes. Passing final checks can be reused for a push only while the validated content and configuration are unchanged.

`bundle exec rake spec` writes HTML line/branch coverage to `coverage/index.html` and LCOV to `coverage/lcov.info`. `bundle exec rake package` builds the production Docker image, runs it against an isolated MongoDB 8.0 container, checks index setup, first-user registration, compiled stylesheet, and `/up`, then removes its own image, containers, and network. This is application packaging, not gem publication.

`bundle exec rake lint` includes RuboCop, prose, embedded Ruby in Markdown, spelling, and a YAML-aware workflow display-name checker. Use Title Case headings and workflow/job/step names, preserve proper names and identifiers, and keep Markdown paragraphs on one source line. Add only reviewed domain terms to `.spellcheck.txt`.

For Ruby lint failures, run `bundle exec rubocop -a` and review safe corrections. Fix remaining offenses when practical; otherwise use `bundle exec rubocop --auto-gen-config`, review its output and inheritance, and avoid broad handwritten cop exclusions.

## Tests

Request specs exercise the actual Rails routes and views. The Mongoid integration spec writes and reads a real document against `MONGODB_TEST_URI`; it removes only its own record. The test helper rejects database names other than `posebook_test` or names beginning with `posebook_test_`, and never uses `MONGODB_URI` as the test fallback.

Account specs cover first-user races, closed public registration, hashed passwords, login/logout, recovery, expired/replayed reset links, concurrent consumption, and session revocation. Test records are explicitly tracked and removed, never globally purged. Setup and test commands create model indexes. Tests lower BCrypt's cost; production keeps the default. Development email is written to `tmp/mail`, and tests never contact SMTP.

Account-settings tests cover profile permissions, verified email changes, conflicting claims, password changes, session revocation, and inactive-account access. System admin accounts remain protected from deactivation. Tests for independent browser sessions inspect each client's own status and location; request redirect matchers use the default client.

Admin user-editing tests cover authorization, allowed contact fields, immediate email changes, session/challenge revocation, competing email claims, inactive accounts, self-edits, and preserving access controls. Admin email changes do not contact an email provider or mark an address verified.

Audit-history tests cover user/venue settings, original/modified values, actors across independent requests and system writes, secret exclusion, no-op/failed saves, retained deletion snapshots, account activation, concurrent email confirmation, and transactional rollback. Use ordinary saves for audited changes; atomic/raw writes bypass `mongoid-history`. Cleanup disables tracking and removes only audit records for owned fixture IDs, never the whole history collection.

Venue tests cover configuration validation, decimal pay, cross-venue isolation, administrator-only mutations, inactive accounts, scoped revocation, and concurrent duplicate role grants against the real unique index. Track membership records before deleting their related fixtures. Do not grant global privileges to represent local schedule access.

Slug tests cover name defaults, editable values, history, duplicate/reserved names, ID-shaped values, unique-index conflicts, scoped shortcuts, and nested management URLs. Production packaging seeds a legacy venue before boot and verifies the entry point backfills its slug. Run `bundle exec rails 'mongoid_slug:set[Venue]'` to backfill existing local venues; it skips documents already containing slugs.

Invitation tests use a MongoDB 8.0 replica set and exercise single-use consumption, transaction rollback under competing account claims, scoped access, existing-account login returns, optional email delivery, expiry/revocation, and preserving membership roles. Track newly accepted accounts and memberships before fixture cleanup. No tests send external messages.

Booking tests exercise real unique claim indexes, competing models/dates, failed-reschedule rollback, required explanations, retained history, private venue/user scope, settings changes, time-zone snapshots, and expiry rollover. Track booking records and their disposable claims. Production code never deletes booking history; test cleanup uses exact owned booking IDs through the collection API because normal model deletion is guarded. Never purge the booking collection.

Drawing-schedule tests cover organizer scope, start-time display/editing, one-off availability, holiday closure/cancellation, restoring regular rules, retained time changes, daylight-saving gaps/offsets, rollback, and bookings racing closures/time changes. Use the shared venue schedule lock for every scheduling mutation; a read-only availability check is insufficient under concurrent writes. Track exception records before fixture cleanup so their related venue and audit entries can be removed safely.

Workflow checker specs exercise valid and invalid human-readable names, ignored identifiers, malformed YAML, and real command exit statuses. Keep fixtures isolated and never delete shared databases or collections. New implementation tests should cover meaningful behavior, authorization boundaries, concurrency, time zones, and errors; use fake delivery providers instead of sending real emails or texts.

Prefer focused tests during development, then final checks before committing. Aim for close to complete line and branch coverage of project-owned runtime code during initial implementation, without trivial tests or excluding meaningful logic. Report remaining gaps. CI keeps Test, Lint, and Package separate, uses explicit `matrix.entry` inline combinations, and reports coverage to Coveralls when the service is available.

Danger runs in PR CI, not as a routine local validation command. Inspect its actual PR result. The Dangerfile uses `danger-changelog`'s update reminder only: its default format parser does not accept this project's dash-style placeholder. The initial scaffold has no changelog entry.

## Pull Requests

Read [DESIGN.md](DESIGN.md) and [AGENTS.md](AGENTS.md). Verify current stable versions and compatibility when adding or updating tools. Work on `<username>/<topic>` branches from `master` in the existing checkout; create separate worktrees only for parallel tasks. For dependent work, branch from the preceding PR, target that branch, and link PRs bottom to top using native GitHub stacks. Inspect status and worktrees before switching and preserve unrelated changes.

Prefer one coherent commit per PR, allowing multiple commits when independently reviewable. AI-assisted commits include the Copilot co-author trailer, and AI-authored PRs/comments disclose AI authorship on behalf of `@dblock`. Squash-merge PRs and never use merge commits. No direct default-branch development pushes or force-pushes to `master`.

Amending or squashing task-owned PR commits needs no further approval. Verify branch ownership, record the remote tip, reconcile remote changes, run checks, then use an explicit `--force-with-lease` against that SHA. Never rewrite another contributor's work.

After an authorized merge, fetch with pruning and verify the PR's merged state on GitHub. Inspect dirty checkouts and dependent stacked PRs before switching to `master` and removing clean, unnecessary task-owned worktrees and local branches. Use `git branch -D` only after confirming the merge and that no unmerged work or dependencies would be lost. Report blocked cleanup; never discard work.

Update affected documentation and keep DESIGN current rather than retaining obsolete decisions. Add features, improvements, and fixes to [CHANGELOG.md](CHANGELOG.md) using `- [#123](https://github.com/dblock/posebook/pull/123): Description - [@dblock](https://github.com/dblock).` with the actual PR and contributor. Append entries chronologically immediately above the placeholder. Predict the next PR number before opening, then verify and correct it. Initial scaffolding and typo-only changes need no entry. Link and document migrations in UPGRADING for incompatible changes to released behavior, including `0.x`.

Follow the version policy in AGENTS: verify release status before bumping, keep unreleased versions unchanged, and synchronize `VERSION` and the Next changelog heading. Use closing references for issues rather than closing them manually. Do not merge, deploy, publish, tag, or configure credentials without explicit authorization. See [RELEASING.md](RELEASING.md).
