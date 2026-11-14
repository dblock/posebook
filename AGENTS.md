# Working on Posebook

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [DESIGN.md](DESIGN.md) before making changes.

## Scope and Layout

Posebook is an invitation-first Rails/Mongoid web application for figure drawing models and organizers. Payments, artist registration, and public model directories are out of scope. Accounts, email recovery, settings, venues, scoped organizer/model access, personal invitations, calendar booking, start times, dated schedule exceptions, and retained history exist; configurable end times and automated reminders do not. Preserve that distinction in documentation.

Runtime code lives in `app/`, configuration in `config/`, request tests in `spec/requests/`, database integration tests in `spec/integration/`, and the tested workflow display-name checker in `script/` and `spec/script/`. Ruby 4.0.9 within 4.0 and Rails 8.1 are supported; test only MongoDB 8.0 to match the deployment target. Use public Rails, Mongoid, and provider APIs. Verify and prefer current stable releases when selecting or updating dependencies while preserving compatibility.

## Invariants

MongoDB is the only application database. Do not introduce Active Record, SQL-backed queues, or Redis without agreement. The scaffold's in-process ActiveJob adapter is not a durable reminder scheduler. Do not enable automated model notifications/reminders until consent, opt-outs, retry behavior, and cancellation handling exist; explicitly requested transactional account/invitation email is separate.

Use one User model with roles. Only blank-installation registration grants `system_admin`; its fixed document ID makes competing claims atomic. Public registration must close afterward; subsequent accounts require invitations. Never accept role fields in public account forms. Keep password hashing and reset-token expiry/single-use behavior intact; password reset must atomically change the digest, remove the token, and invalidate all sessions. Provider messaging consent requirements apply to future model notifications, not explicitly requested account recovery.

Every model roster and schedule belongs to a venue. Booking mutations use replica-set transactions and unique `ModelBookingClaim` venue/date and venue/user indexes. Never delete or overwrite historical `ModelBooking` dates; retain cancellation/rescheduling explanations and link replacement records. Only disposable expired/canceled claims may be removed. UTC expiry snapshots let past bookings display Completed and release claims without a background job. Store instants in UTC and calculate civil dates in the venue's time zone, including daylight saving changes. Keep contacts and model rosters private; filter email, phone, and authentication tokens from logs.

All booking, schedule-exception, and venue-settings mutations share the transactional venue schedule lock and reload state on retries. Preserve this write barrier so closures/time edits cannot race new bookings. Assigned organizers may manage dated exceptions, not general venue settings. Require short explanations; closing a booked date atomically cancels its retained booking, while time edits append an attributed change and keep the booking. Never silently delete exception history or overwrite booking time-change entries.

Only system admins configure venues or grant/revoke organizer access. `manage_schedule` and `model` belong to venue memberships, never global user roles. Scope views through `Venue.visible_to` and invitation management through `Venue.managed_by`; never trust a URL or role form parameter for authorization. Preserve the unique venue/user membership index and atomic role grants/revocation. Revocation and deactivation retain membership/history. Personal model invitations are single-use bearer links; persist only their digests and atomically create accounts, consume invitations, and grant membership in a replica-set transaction.

Venue URLs use `mongoid-slug` with name-derived defaults, optional custom values, and retained slug history. Preserve ID-based URLs and scope slug lookups through the same authorization criteria. The root shortcut route belongs last, after application routes; reserve conflicting path names. Production startup creates slug indexes and runs the gem's missing-slug task, never regenerating existing slugs as a migration.

`mongoid-history` audits whitelisted User/Venue business fields, never credentials, authentication challenges, or session secrets. Keep request actor context scoped and allow nil for anonymous/system writes. Audited email confirmation and account activation changes require fresh-document transactional saves; preserve expiry, token, and protected-admin predicates on retries. Atomic/raw updates bypass history; do not use them for normal audited field changes. No history or undo interface exists.

Tests use `MONGODB_TEST_URI`, never the development or production connection. The test database guard requires `posebook_test` or a `posebook_test_` prefix. Delete only records owned by a test, not entire collections or databases. Keep real network-provider calls out of tests.

## Validation and Documentation

Run `bundle exec rake spec` and `bundle exec rake lint` before every development push. Run `bundle exec rake package` before committing changes to packaging, runtime dependencies, configuration, or HTTP entry points. Reuse passing results only if the tested content and configuration have not changed. The package check builds and runs the actual production Docker image and cleans up its own container and image.

Prefer focused behavior tests while developing, followed by final validation before committing. `bundle exec rake spec` produces line and branch coverage in `coverage/index.html` and `coverage/lcov.info`. During implementation, aim for close to complete project-owned runtime coverage without trivial assertions or excluding real logic; report meaningful remaining gaps.

`bundle exec rake lint` checks Ruby, Markdown prose, embedded Ruby, spelling, and YAML workflow/job/step display names. Use Title Case for human-readable Markdown headings and workflow display names, preserving proper names, acronyms, and machine identifiers. Keep prose paragraphs on one source line. Fix Ruby offenses with `bundle exec rubocop -a` first and review corrections; if necessary, use `bundle exec rubocop --auto-gen-config` and review generated configuration rather than broadly disabling cops. Review `.spellcheck.txt` additions and fix typos instead of accepting them.

Keep `Test`, `Lint`, and `Package` workflows separate. Use only `matrix.entry` lists of compact inline objects, with no `include`, `exclude`, or separate Cartesian axes. Maintain Coveralls reporting and Ruby Danger checks. Danger runs in PR CI, not as a routine local command; inspect its actual PR result. Its changelog check currently reminds contributors about updates, not format validation.

Maintain README links to every project Markdown document. Keep DESIGN focused on current behavior, the agreed design, and still-relevant rationale, not an implementation diary. Features, improvements, and fixes require attributed changelog entries with actual PR numbers, appended above the placeholder; initial scaffolding and typo-only changes do not. Predict the number before opening a PR and verify it afterward. Add and link UPGRADING when changing released behavior incompatibly, including within `0.x`.

## Git and Release Safety

Start topic branches from `master` with `git switch -c dblock/<topic> master`, using the actual contributor login in place of `dblock`. Use the existing checkout unless parallel tasks require separate worktrees. Preserve unrelated tracked and untracked changes; inspect status and worktrees before switching. Never develop directly on or force-push `master`.

Stack dependent PRs sequentially: branch from the preceding PR's pushed tip, target its branch, and register bottom-to-top native GitHub stack membership. Do not mix independent changes into a stack or recreate partially merged stack metadata.

Prefer one coherent commit per PR; independently reviewable commits are acceptable. Task-owned PR commits may be amended or squashed without another approval: verify ownership, record the remote tip, reconcile remote changes, validate, and push only with `--force-with-lease` against the recorded SHA. Never rewrite another contributor's work. Squash-merge PRs; merge commits are prohibited.

Include `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` in AI-assisted commits. AI-authored PRs and comments must disclose AI authorship on behalf of `@dblock`. Use closing issue references in implementation PRs; leave issues open until merge.

After an authorized merge, fetch with pruning, verify GitHub's merged state, inspect dirty checkouts and dependent PRs, switch safely to `master`, and remove only clean, unnecessary task-owned worktrees and topic branches. Squash/rebase merges may require `git branch -D`, but only after verifying no unmerged work or dependencies would be lost. Never delete dirty worktrees or active PR branches.

No merge, deployment, registry credentials, publication, tags, or releases without authorization. Posebook is an application, not a registry package; follow [RELEASING.md](RELEASING.md) for provisional deployment guidance. Never overwrite published versions or release tags.

Before any version bump, establish whether the current version was released; ask if that cannot be determined. Keep unreleased `0.1.0` unchanged. After release, feature or breaking changes in `0.x` increment minor and reset patch; features in `1.x` increment minor while preserving patch. Ask before a major bump for breaking changes in `1.x`. Keep `VERSION` and the Next changelog heading synchronized; update any future version declarations and lockfiles together.
