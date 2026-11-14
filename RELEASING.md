# Releasing

## Status

These are provisional deployment instructions, not a completed release pipeline or authorization to deploy. Posebook is a web application, not a published Ruby gem or npm package. Version `0.1.0` has not been released. No registry badge or package-publication workflow is appropriate yet.

## Versioning and Validation

Establish whether the current version has actually been released before changing it; ask if release status is uncertain. Keep unreleased `0.1.0` unchanged. After release, features and breaking changes in `0.x` increment minor and reset patch. Features in `1.x` increment minor while preserving patch; ask before a major bump for breaking changes. Synchronize `VERSION`, the Next changelog heading, and any future version declarations or lockfile metadata. Record released sections as `## <version> (YYYY/MM/DD)` and document migrations for incompatible changes.

Before an authorized release, run:

```sh
bundle exec rake spec
bundle exec rake lint
bundle exec rake package
```

Review the actual image's files and runtime behavior; ensure no local secrets, credentials, test fixtures, development dependencies, or generated coverage are included. The package task builds and smoke tests a temporary image and removes it afterward; it does not produce a retained release artifact.

## Future Deployment Procedure

With explicit authorization, build and retain an image from the reviewed commit, validate that exact artifact, record its immutable digest, and deploy that same digest rather than rebuilding after validation. If publishing an image to a registry, authorize and authenticate through the deployment platform; never place tokens in source or overwrite an existing version tag.

Configure managed MongoDB, `MONGODB_URI`, `SECRET_KEY_BASE`, and `APP_HOST` through DigitalOcean's secret/environment settings, with TLS terminating at its proxy. The entry point creates declared indexes, so its database user needs index permissions. Register the first user immediately after a blank deployment; public setup has no secret by design and closes after that account exists.

Set `SMTP_ADDRESS`, `MAIL_FROM`, and any required `SMTP_PORT`, `SMTP_USERNAME`, and `SMTP_PASSWORD` before enabling email recovery in production. Without SMTP configuration, reset requests report unavailable delivery. Verify actual reset delivery with authorization before inviting users. Model reminders still require their own provider and durable-worker implementation. Verify the deployed revision, TLS, allowed hostname, `/up`, real MongoDB connectivity, and relevant user flows. `/up` alone is not a database-readiness check.

Tag creation, a GitHub Release, registry publication, credential setup, and deployment each require explicit authorization. Verify any authorized release tag points to the reviewed revision and the deployed image digest matches the validated artifact. Do not overwrite tags or automatically retry publication when verification fails; inspect the registry and deployment state first.

Rollback and data/index migration procedures must be defined and tested before production functionality ships. No release automation is configured, and ordinary development remains PR-only.
