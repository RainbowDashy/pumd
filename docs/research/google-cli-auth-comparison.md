# Google CLI authentication comparison

Research date: 2026-08-03

## Conclusion

Neither `googleworkspace/cli` nor `glotlabs/gdrive` removes the need for an
OAuth client. Both make the user own a Google Cloud project and Desktop OAuth
client, then perform the installed-application OAuth flow themselves. The main
difference from `pumd` is that their normal interactive path does not depend on
Application Default Credentials (ADC).

For `pumd`, the reusable pattern is a dedicated installed-app authorization
module with a loopback callback, refresh-token caching, secure storage, and ADC
as an explicit fallback. `pumd` should continue requesting only `drive.file`.

## Current state (2026-08-04)

Guided Project Authorization setup no longer uses `gcloud`. `pumd` opens the
Enable Docs API flow and the Auth Clients page, waits for the downloaded
Desktop client JSON, validates it, and performs the direct `drive.file`
installed-app flow. `gcloud` remains only as an ADC provisioning path; the
command below is that route, not Project Authorization setup. The tool
comparisons above still describe the two researched CLIs as of 2026-08-03.

## `googleworkspace/cli`

- `gws auth setup` uses `gcloud` for account/project selection and API
  enablement, and configures the consent screen. Current source still requires
  the user to create a Desktop OAuth client in Cloud Console and paste its
  client ID and secret; automated client creation was removed. See
  [`setup.rs`](https://github.com/googleworkspace/cli/blob/a3768d0e82ad83cca2da97724e46bea4ff0e6dbd/crates/google-workspace-cli/src/setup.rs#L1417-L1583).
- `gws auth login` performs a direct installed-app flow. It prints an
  authorization URL and receives the result on a loopback HTTP listener using
  an automatically chosen port. See
  [`auth_commands.rs`](https://github.com/googleworkspace/cli/blob/a3768d0e82ad83cca2da97724e46bea4ff0e6dbd/crates/google-workspace-cli/src/auth_commands.rs#L114-L158) and the normal
  [`yup-oauth2` path](https://github.com/googleworkspace/cli/blob/a3768d0e82ad83cca2da97724e46bea4ff0e6dbd/crates/google-workspace-cli/src/auth_commands.rs#L181-L227).
- It stores the resulting `authorized_user` credentials encrypted with
  AES-256-GCM in `~/.config/gws/credentials.enc`. The encryption key is kept in
  the OS keyring, with a local `~/.config/gws/.encryption_key` fallback. See
  [`credential_store.rs`](https://github.com/googleworkspace/cli/blob/a3768d0e82ad83cca2da97724e46bea4ff0e6dbd/crates/google-workspace-cli/src/credential_store.rs#L357-L453).
- Runtime credential precedence is: explicit access token, explicit credential
  file, encrypted `gws` credentials, plaintext `gws` credentials, then ADC.
  Authorized-user and service-account files are supported. See
  [`auth.rs`](https://github.com/googleworkspace/cli/blob/a3768d0e82ad83cca2da97724e46bea4ff0e6dbd/crates/google-workspace-cli/src/auth.rs#L185-L210).
- Headless use is handled by exporting credentials after an interactive login,
  or by supplying a credential file, service account, or pre-obtained access
  token. See the repository's
  [authentication documentation](https://github.com/googleworkspace/cli/blob/a3768d0e82ad83cca2da97724e46bea4ff0e6dbd/README.md#authentication).

This is the stronger model for `pumd`: direct user OAuth, a small auth command
surface, encrypted refresh-token storage, and several explicit automation
adapters.

## `glotlabs/gdrive`

- `gdrive account add` prompts for the user's own Client ID and Client Secret,
  requests tokens, and names the account from Drive's `about.user` response.
  See [`add.rs`](https://github.com/glotlabs/gdrive/blob/855155649a5911565c9134eac6a1f9b9bf235494/src/account/add.rs#L9-L58).
- Its setup guide requires the user to create a Cloud project, enable Drive,
  configure consent, add a test user, create a Desktop OAuth client, and publish
  the OAuth app. See
  [the credential guide](https://github.com/glotlabs/gdrive/blob/855155649a5911565c9134eac6a1f9b9bf235494/docs/create_google_api_credentials.md#L5-L38).
- It uses an installed-app flow with a fixed loopback listener on port 8085 and
  prints the authorization URL. See
  [`hub.rs`](https://github.com/glotlabs/gdrive/blob/855155649a5911565c9134eac6a1f9b9bf235494/src/hub.rs#L56-L74).
- It requests broad `drive` and `drive.metadata.readonly` scopes rather than
  `drive.file`. See
  [`add.rs`](https://github.com/glotlabs/gdrive/blob/855155649a5911565c9134eac6a1f9b9bf235494/src/account/add.rs#L24-L30).
- Account secrets and tokens live below `~/.config/gdrive3/`. They are
  plaintext JSON protected with Unix file permissions rather than encryption
  or an OS keyring. See
  [`app_config.rs`](https://github.com/glotlabs/gdrive/blob/855155649a5911565c9134eac6a1f9b9bf235494/src/app_config.rs#L101-L165).
- Remote use is supported by exporting the account directory to an archive,
  copying it, and importing it on the server. There is no ADC, service-account,
  environment-token, or device-flow adapter in the source. See the
  [remote-server instructions](https://github.com/glotlabs/gdrive/blob/855155649a5911565c9134eac6a1f9b9bf235494/README.md#using-gdrive-on-a-remote-server).

The useful parts for `pumd` are the explicit account command and cached refresh
token. The broad scope, fixed port, plaintext storage, and long BYO-client setup
should not be copied.

## Why the current `gcloud` command fails

Passing `--scopes` replaces `gcloud`'s default list. Current `gcloud auth
application-default login` then requires `cloud-platform` to be present even
when `--client-id-file` is supplied. Google documents that local user ADC
normally includes `cloud-platform`, and its examples that combine Drive with
ADC include both scopes. See Google's
[ADC documentation](https://docs.cloud.google.com/docs/authentication/application-default-credentials#credentials_set_up_adc) and
[Drive/ADC example](https://docs.cloud.google.com/bigquery/docs/external-data-drive#authenticate_and_enable_drive_access).

The immediate workaround is:

```console
gcloud auth application-default login \
  --client-id-file=oauth-client.json \
  --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/drive.file
```

This is an ADC/`gcloud` constraint, not an installed-app OAuth requirement. A
direct Desktop OAuth flow can request only `drive.file`, which Google classifies
as a narrow, non-sensitive scope. See the
[Drive scope guide](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
and [installed-app OAuth guide](https://developers.google.com/identity/protocols/oauth2/native-app).

## Recommendation for `pumd`

1. Correct the current ADC command immediately by including `cloud-platform`,
   while explaining that this is a temporary compatibility path.
2. Add `pumd auth login`, `status`, and `logout` using direct Desktop OAuth,
   PKCE, a random loopback port, state validation, and only `drive.file`.
3. Encrypt refresh credentials using the OS keyring, with a permission-hardened
   file adapter for headless environments.
4. Keep ADC as an explicit development/CI adapter rather than the default
   interactive path.
5. Decide separately whether `pumd` will ship a maintainer-owned, published
   OAuth client. Without one, users still need to create a Cloud project and
   Desktop client, as both compared CLIs do. With one, first publish can become
   a single browser-consent step, but the maintainer owns verification, quota,
   abuse, and support obligations.
