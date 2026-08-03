# npm nightly publishing

The `Nightly` GitHub Actions workflow packages the Windows x86-64, Linux x86-64,
and Apple Silicon macOS binaries into one public `@p0nyyy/pumd` npm package. A
Node.js launcher selects the native binary for the install platform. The
workflow publishes a version shaped like
`0.1.0-nightly.<short-commit>` under the `nightly` dist-tag. The commit prefix is
normally seven characters; if a numeric prefix beginning with zero would
violate SemVer, it is extended until it includes a hexadecimal letter. If that
commit version is already present, the workflow validates the package and
skips publishing it again.

The npm job is enabled only when the repository variable
`NPM_PUBLISH_ENABLED` is exactly `true`. Publishing uses npm trusted publishing
with GitHub's short-lived OIDC credential; the repository must not store an
`NPM_TOKEN` publishing secret.

## Trusted publishing configuration

The `@p0nyyy/pumd` package has a GitHub Actions trusted publisher with these
values:

- Organization or user: `RainbowDashy`
- Repository: `pumd`
- Workflow filename: `nightly.yml`
- Environment: none
- Allowed action: `npm publish`

Keep `NPM_PUBLISH_ENABLED=true`; the workflow's `id-token: write` permission
supplies the OIDC credential used by npm. A workflow run on a branch other than
`main` builds and tests the binaries but skips both publication jobs.

## Publish stable versions later

Stable npm releases should use the same package layout but derive the exact
version from a release tag and publish under the default `latest` dist-tag.
Nightly publishing must continue to pass `--tag nightly` so a prerelease never
replaces `latest`.
