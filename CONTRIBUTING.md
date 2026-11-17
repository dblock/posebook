# Contributing

Read [Design](DESIGN.md), [Coding Guidance](AGENTS.md), and, for interface work, [UI Conventions](docs/ui-conventions.md). [Operating Posebook](docs/operating.md) covers configuration and deployment; [Background Jobs](docs/background-jobs.md), [Google Calendar Setup](docs/google-calendar.md), and [Upgrading](UPGRADING.md) cover their respective operations.

## Setup and Validation

Install Ruby 4.0.9, Bundler, MongoDB 8.0, Docker, libvips, and Chrome/Chromium for browser tests. Tests target MongoDB 8.0, matching deployment. On macOS, install libvips with `brew install vips`; on Ubuntu 24.04/Debian 13, use `sudo apt-get install libvips42t64`. No production credentials are needed.

Use an existing replica set or create a dedicated local container on an unused port:

```sh
docker run --detach --name posebook-mongo --publish 127.0.0.1:27017:27017 mongo:8.0 --replSet rs0 --bind_ip_all
docker exec posebook-mongo mongosh --quiet --eval 'rs.initiate({_id:"rs0",members:[{_id:0,host:"127.0.0.1:27017"}]})'
bin/setup --skip-server
bundle exec rake spec
bundle exec rake lint
bundle exec rake package
```

Wait for a writable primary before setup. For another port, use the same port inside/outside the container and advertise it in the replica-set configuration; set `MONGODB_URI` and `MONGODB_TEST_URI` with `?replicaSet=rs0`. Never use `directConnection=true`, which disables driver transactions. Do not overwrite another project's container; stop your own with `docker stop posebook-mongo` when done.

Run affected tests while developing, then final tests and lint before committing/pushing. Documentation-only changes need lint. Run packaging before committing changes to packaging, runtime dependencies, configuration, or HTTP entry points. Reuse passing results while the tested content/configuration is unchanged; do not wait for CI after successful local checks.

`bundle exec rake lint` checks Ruby, Markdown prose, embedded Ruby, spelling, and YAML workflow display names. Use Title Case headings/display names and one source line per Markdown paragraph. Review `.spellcheck.txt` additions. For Ruby offenses, start with `bundle exec rubocop -a`; review corrections and any generated configuration rather than broadly disabling cops.

`bundle exec rake package` builds the production image and tests it against isolated MongoDB, including indexes, transaction rollback, first-user registration, compiled CSS, and `/up`. It cleans up only its own image, containers, volumes, and network. CI uses `ruby bin/package --image posebook-package:TAG` to check an already built local image without deleting it.

## Tests

Tests require a separate `MONGODB_TEST_URI` named `posebook_test` or beginning with `posebook_test_`; they never fall back to the development URI. Use real MongoDB transactions, indexes, and libvips processing, but fake external providers. Track fixtures and remove only owned records/files, never collections or databases. Development mail appears in `tmp/mail` when the worker runs; tests use in-memory delivery.

Add focused behavioral tests for changed permissions, concurrency, time zones, errors, and other relevant boundaries. Avoid assertions for purely cosmetic spacing, colors, font sizes, or fixed element dimensions; keep layout checks for real overflow and usability regressions. Booking requests must carry explicit displayed revisions; reload fixtures only when modeling a fresh view. Booking cleanup uses exact owned IDs because normal deletion is guarded. Audit cleanup disables tracking and removes only owned history entries.

`bundle exec rake spec` writes line/branch coverage to `coverage/index.html` and `coverage/lcov.info`. Inspect meaningful gaps without adding trivial assertions or excluding runtime code.

CI keeps Test, Lint, and Package separate, uses explicit inline `matrix.entry` combinations, and reports Coveralls coverage. Danger runs only in PR CI; inspect its actual result. Its changelog check is a reminder, not format validation.

### Browser Tests

`bundle exec rspec spec/system` drives headless Chrome through Capybara/Cuprite against an in-process Puma server and the test database; the full suite includes these specs. Set `BROWSER_PATH` for a nonstandard Chrome/Chromium binary.

Create fixtures with database helpers and `track_record` records created through browser flows; tracking is not automatic. `spec/support/browser_helpers.rb` supplies sign-in/out, desktop/phone/narrow viewports, overflow checks, disabled JavaScript, clipboard stubs, and screenshots. Group layout checks by viewport to avoid repeated browser resizing, and reuse each loaded page for related checks. Browser tests default `FERRUM_CLICK_WAIT` to `0.01`, shortening the fixed post-click pause while retaining a navigation grace period and unchanged waiting timeouts; wait for visible results before checking asynchronous actions or starting another navigation. Set `BROWSER_SCREENSHOTS=tmp/screenshots` for captures; never commit them. Embed meaningful interface captures as GitHub-hosted PR attachments and verify their published URLs.

## Performance Benchmarks

Use an explicitly disposable local benchmark database:

```sh
MONGODB_TEST_URI='mongodb://127.0.0.1:27017/posebook_test_benchmark?replicaSet=rs0' bundle exec ruby bin/benchmark --samples 5
```

The command accepts only `posebook_test_benchmark` or underscore-prefixed variants, creates a synthetic multi-program corpus with booking history and real optimized photos, and cleans up only its records/files. It sends no messages and never deletes collections.

JSON reports request paths, warm latency estimates, allocations, response size, collection read counts, database time, and indexed query work across public/participant/admin pages and images. Setup, login, warm-up, browser, and network time are excluded. Compare on the same machine/corpus; shared load and small samples make timings indicative. Regression tests enforce bounded database work rather than latency thresholds.

## Pull Requests

Use `<username>/<topic>` branches in the existing checkout, starting from `master` or the prerequisite PR branch. Inspect status and worktrees before switching; preserve unrelated work. Create separate sibling worktrees only for parallel tasks. Dependent PRs target the preceding branch and use native GitHub stack registration.

Keep each PR to one coherent commit. AI-assisted commits include the Copilot co-author trailer; AI-authored descriptions/comments disclose AI acting on behalf of `@dblock`. Use rebase merges, never squash or merge commits. Do not merge or deploy without explicit authorization, or push development changes directly to `master`.

Before rewriting a task-owned branch, verify ownership, record its fetched remote tip, reconcile remote changes, and validate. Push with an explicit `--force-with-lease` against that SHA; never rewrite another contributor's work or force-push `master`.

After an authorized merge, fetch/prune and verify merged state on GitHub. Inspect dirty checkouts and dependent PRs before removing only clean, unnecessary task-owned worktrees/branches. Never discard work or delete branches with active dependencies.

Keep documentation focused: Design for architecture/invariants, guides for usage/operations, and this file for development commands. Remove superseded proposals and implementation diaries. Verify current stable versions and compatibility when updating tools/dependencies.

Add meaningful features, fixes, and improvements above the placeholder in [Changelog](CHANGELOG.md), using `- [#123](https://github.com/dblock/posebook/pull/123): Description - [@dblock](https://github.com/dblock).` with actual attribution. Predict the PR number before opening, then verify/correct it. Scaffolding and typo-only changes need no entry. Use closing issue references rather than closing implementation issues manually.

Production is continuously updated, without release versions, tags, or registry publication. Document required manual migrations in Upgrading; deployment authorization is separate from development.
