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

Open [localhost:3000](http://localhost:3000). This scaffold serves a placeholder page and `/up` liveness endpoint. Model invitations, registration, booking, and reminders are not implemented yet.

## Configuration

| Variable           | Default                                                         | Purpose                                                                                          |
| ---                | ---                                                             | ---                                                                                              |
| `MONGODB_URI`      | `mongodb://127.0.0.1:27017/posebook_development` in development | MongoDB connection; required in production.                                                      |
| `MONGODB_TEST_URI` | `mongodb://127.0.0.1:27017/posebook_test`                       | Isolated test connection; database names must be `posebook_test` or start with `posebook_test_`. |
| `APP_HOST`         | `enochs.dblock.org`                                             | Production hostname allowed by Rails and used in future email links.                             |
| `SECRET_KEY_BASE`  | Rails development default                                       | Required production secret, supplied through deployment settings.                                |
| `PORT`             | `3000`                                                          | HTTP listen port behind an HTTPS-terminating proxy.                                              |

Export environment variables in your shell or configure them through DigitalOcean. `.env.example` documents local examples; Rails does not load `.env` files automatically. Production email delivery is disabled until notification functionality is implemented. No email or SMS credentials are needed for the scaffold.

## Contributing

Read [Contributing](CONTRIBUTING.md), [Design](DESIGN.md), [Changelog](CHANGELOG.md), [Releasing](RELEASING.md), and [Working on Posebook](AGENTS.md).

## License

[MIT License](LICENSE.txt).
