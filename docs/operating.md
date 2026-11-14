# Operating Posebook

Posebook is a self-hosted Rails application for figure-drawing venues. The hosted [instance](https://posebook.dblock.org/) serves Enoch's figure-drawing sessions; see the [session overview](https://art.dblock.org/2026/05/25/figure-drawing-at-enochs.html). You can install and run a separate instance for your own venue.

## Stack and Local Development

Posebook uses Rails 8.1, Ruby 4.0.9 (within Ruby 4.0), and MongoDB 8.0. MongoDB must run as a replica set for booking, invitation, and account transactions. See [Contributing](../CONTRIBUTING.md) for prerequisites, local replica-set setup, and validation commands.

Clone the repository, install its dependencies, and start the development server:

```sh
git clone https://github.com/dblock/posebook.git
cd posebook
bin/setup --skip-server
bin/dev
```

`bin/setup` creates declared MongoDB indexes; it does not run historical migrations or slug backfills. Normal venue and program saves generate slugs. Set `MONGODB_URI` if the development database is not `mongodb://127.0.0.1:27017/posebook_development`. Set `MONGODB_TEST_URI` to a separate test database named `posebook_test` or beginning with `posebook_test_`. Rails does not load `.env` files automatically; `.env.example` contains local examples.

## Configuration

| Variable                                      | Purpose                                                                                     |
| ---                                           | ---                                                                                         |
| `MONGODB_URI`                                 | MongoDB connection; required in production.                                                 |
| `MONGODB_TEST_URI`                            | Isolated test connection.                                                                   |
| `APP_HOST`                                    | Allowed application hostname and host used in email links; defaults to `enochs.dblock.org`. |
| `SECRET_KEY_BASE`                             | Required production session and encryption secret.                                          |
| `PORT`                                        | HTTP port behind the HTTPS-terminating proxy; defaults to `3000`.                           |
| `SMTP_ADDRESS`, `MAIL_FROM`                   | Enable production password recovery and email-change confirmations.                         |
| `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Optional SMTP connection settings; STARTTLS is enabled automatically.                       |

Without SMTP configuration, account recovery reports that email is unavailable. SMS delivery is not implemented.

## Production Operations

Production is continuously updated: each production update replaces the currently running application. There are no per-release versions, release tags, or registry publications. DigitalOcean App Platform hosts the linked instance; this repository's package workflow builds and smoke-tests a temporary image rather than publishing or deploying it.

Configure the Dockerfile, terminate TLS at the host's proxy, and store `MONGODB_URI`, `SECRET_KEY_BASE`, and any SMTP password as encrypted settings. The MongoDB user needs permission to create and remove indexes. The production image listens on port `3000`; `/up` checks application liveness, not database readiness.

At startup, the production entry point creates declared indexes and then starts the HTTP server. It no longer converts collections, fields, roles, or Instagram data, and does not backfill slugs. Follow [Upgrading](../UPGRADING.md): the sole instance must finish the conversion from PR #52 before deploying this version. Normal profile edits still accept Instagram handles or profile URLs. Preserve MongoDB replica-set connection options from the provider and do not set `directConnection=true`, which disables transaction support.

After a blank deployment, register the first account promptly; public registration closes once the first account exists. After each production update, verify the live site and relevant user flows. Coordinate database migrations with application compatibility; rolling back application code does not roll back data changes.

Optional New Relic reporting uses `NEW_RELIC_LICENSE_KEY`; `NEW_RELIC_APP_NAME` can override the default `Posebook`, and `NEW_RELIC_AGENT_ENABLED=false` disables production reporting. Monitoring is disabled in development and tests and excludes request attributes, MongoDB queries, exception messages, application log forwarding, and browser monitoring.

For project design and invariants, see [Design](../DESIGN.md); for code changes and tests, see [Contributing](../CONTRIBUTING.md).
