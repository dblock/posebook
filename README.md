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

Open [localhost:3000](http://localhost:3000) and create the first user with a name, email, and password of at least 12 characters. That user receives the global `system_admin` role. Public registration then closes; later accounts will require invitations, which are not implemented yet. Sign in with email/password and use "Forgot your password?" for email recovery. Passwordless access and phone recovery are deferred.

Development reset emails are written to `tmp/mail/`. Reset links expire after 30 minutes, can be used once, and invalidate existing sessions when used. Model registration, booking, and reminders are not implemented yet. `/up` checks application liveness, not database readiness.

Use **Account Settings** to edit your name, optional international-format phone number, or password. Changing email requires your current password and confirmation at the new address; the old email remains your login and recovery address until confirmed. Phone numbers are stored but are not verified or used for recovery or messaging. Password changes retain the current browser session and revoke other sessions and outstanding recovery or email-change links.

Non-admin users can deactivate their accounts with their current password; history is retained. System admins can deactivate or reactivate users from **Users**. System admin accounts cannot be deactivated until role transfer is available, so administrator access cannot be lost. Deactivation revokes sessions and recovery links and prevents login and recovery. Public registration stays closed even when accounts are inactive.

Use **Venues** to create a venue as a system admin, configure its address, IANA time zone, informational model pay in USD, instructions, and booking horizon, then grant `manage_schedule` to existing active users. Defaults are `America/New_York`, $140, and six months; each venue can have different settings. Organizers see only their assigned venues and cannot edit venue settings, manage other users, or assign organizers. System admins can manage all venues.

Removing schedule access preserves the membership record and immediately removes access to that venue. Deactivated users retain their assignments but cannot sign in until reactivated. Only system admins see organizer contact details and the existing-user selector. Creating accounts by invitation, generating schedules, booking, and sending model reminders remain future work.

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

`bin/setup` and the production Docker entry point create declared MongoDB indexes before serving requests. Configure the database user to permit index creation.

## Contributing

Read [Contributing](CONTRIBUTING.md), [Design](DESIGN.md), [Changelog](CHANGELOG.md), [Releasing](RELEASING.md), and [Working on Posebook](AGENTS.md).

## License

[MIT License](LICENSE.txt).
