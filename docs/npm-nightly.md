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

The npm job is disabled unless the repository variable
`NPM_PUBLISH_ENABLED` is exactly `true`. This keeps the GitHub nightly release
working while npm ownership and authentication are being bootstrapped.

## Bootstrap the package

1. Confirm that the public `@p0nyyy/pumd` package name remains available on npm.
2. Create a granular npm access token with the shortest practical expiration.
   Set **Packages and scopes** to **Read and write** for **All Packages**, because
   `@p0nyyy/pumd` cannot be selected before its first publication, and enable
   **Bypass 2FA** for the non-interactive workflow. Save it as the GitHub Actions
   repository secret `NPM_TOKEN`. Do not grant organization-management access.
3. Set the GitHub Actions repository variable `NPM_PUBLISH_ENABLED` to `true`.
4. Manually run `.github/workflows/nightly.yml` on `main`. The first successful
   run creates the package and publishes the commit version with the `nightly`
   dist-tag.

## Switch to trusted publishing

After the first package version exists, open the `@p0nyyy/pumd` package settings
on npm and add a GitHub Actions trusted publisher with these exact values:

- Organization or user: `RainbowDashy`
- Repository: `pumd`
- Workflow filename: `nightly.yml`
- Environment: none
- Allowed action: `npm publish`

Run the workflow again after a new commit and confirm that the npm publication
succeeds through trusted publishing. Then delete the `NPM_TOKEN` repository
secret and revoke the temporary token on npm. Keep `NPM_PUBLISH_ENABLED=true`;
the workflow's `id-token: write` permission supplies the short-lived OIDC
credential used by npm.

## Publish stable versions later

Stable npm releases should use the same package layout but derive the exact
version from a release tag and publish under the default `latest` dist-tag.
Nightly publishing must continue to pass `--tag nightly` so a prerelease never
replaces `latest`.
