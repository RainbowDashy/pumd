# pumd

`pumd` publishes local Markdown as a native Google Doc that is pleasant to read,
edit, comment on, and review.

The local Markdown file remains the authoritative source. Publishing it again
should update the existing Google Doc safely and incrementally instead of
replacing the entire document.

> **Current behavior:** `pumd publish <path>` creates a Publication on its
> first run and safely updates that Publication thereafter. An update reads the
> Managed Tab, compares local Markdown and Google Docs changes with the
> Published Baseline, and writes only non-conflicting local changes in one
> revision-checked Google Docs batch. Unresolved comments, overlapping edits,
> ambiguous remote alignment, and concurrent edits block safely; there is no
> force bypass or legacy-document discovery. `--dry-run` performs the same
> checks without remote or Publication Registry writes.

## Nightly binaries

The latest `main` commit is built with the latest stable MoonBit toolchain every
night at approximately 02:23 Asia/Shanghai. The GitHub Actions workflow can also
be run manually; only a run on `main` publishes a release. Successful native
builds for Windows x86-64, Linux x86-64, and Apple Silicon macOS replace the
assets in the rolling
[`nightly` prerelease](https://github.com/RainbowDashy/pumd/releases/tag/nightly).

The same builds are published to npm when npm publishing is enabled for the
repository. Install the latest successful npm nightly globally with:

```console
npm install --global @p0nyyy/pumd@nightly
```

This installs the `pumd` command. The npm package requires Node.js 18 or newer
for its small platform launcher, then executes the bundled native binary. Each
npm version identifies its source commit as
`0.1.0-nightly.<short-commit>`; the `nightly` dist-tag points to the most
recently published commit.

Nightly artifacts are intended for testing. The `nightly` tag and its release
assets move in place, builds may be unstable, and older nightlies are not kept
as releases. Use the attached `SHA256SUMS` file to verify a download. The
workflow runs the complete local native release suite and a CLI smoke test, but
does not run the opt-in test that creates a real Google Doc.

Maintainer setup for the first npm publication and trusted publishing is
documented in [`docs/npm-nightly.md`](docs/npm-nightly.md).

## Problem

Markdown is a good local authoring format, while Google Docs is often the most
convenient place for peer review. Moving between them is frustrating:

- HTML and CSS imports are inconsistent.
- Uploading a new copy produces unstable links and scattered review history.
- Replacing the whole document can detach comments and suggestions.
- Code blocks, tables, and spacing frequently need manual cleanup.
- Existing tools expose Google Docs mechanics instead of a publishing workflow.

## Goals

### Keep Markdown authoritative

Authors should continue editing ordinary local Markdown with their preferred
editor and version-control workflow. Publishing must not require hidden markup,
manual Google Docs formatting, or maintaining two independent sources of truth.

### Produce a native Google Doc

The published result must be a real, editable Google Doc—not an uploaded
Markdown file, rendered web page, PDF, or image. Reviewers should be able to use
normal Google Docs comments, suggestions, links, lists, tables, and text
selection.

### Update incrementally

After the first publication, subsequent publishes should modify only content
that changed locally. Unchanged Google Docs content should remain untouched so
that formatting, comments, suggestions, and review context stay anchored.

### Be safe around collaboration

Publishing should detect remote edits, active comments, suggestions, and
concurrent changes that overlap a local change. Ambiguous or conflicting updates
must stop with an understandable explanation rather than silently overwriting a
reviewer's work. Explicit overrides may exist, but must never be the default.

### Apply stable, readable defaults

Documents should look coherent without a stylesheet or per-document setup.
Headings, paragraphs, blockquotes, lists, links, tables, images, inline code,
and fenced code blocks should have consistent native Google Docs formatting.
Fenced code must remain editable and commentable, with a legible monospaced
presentation.

### Keep the everyday interface small

The common workflow should require one obvious command:

```console
pumd publish proposal.md
```

`pumd publish` creates a document when the source is unlinked and safely updates
its existing Publication when it is linked. Google document IDs, Managed Tab
IDs, UTF-16 indexes, named ranges, and request ordering are implementation
concerns that the author should not need to manage.

### Make every write inspectable

Authors should be able to preview what would change before publishing. Results
and failures should explain which Markdown sections are affected and why a push
is safe, blocked, or requires intervention.

## Current setup and publishing

### Toolchain, target, and dependencies

The executable supports the MoonBit `native` target only. The current checkout
has been validated with this toolchain:

```text
moon 0.1.20260724 (5f1406a 2026-07-24)
moonc v0.10.5+5e7afb0c0 (2026-07-27)
```

The direct dependency contract in `moon.mod` is pinned exactly to:

- `moonbitlang/x@0.4.46`
- `ryota0624/googleauth@0.2.0`
- `ryota0624/googleapis@0.4.1`
- `moonbitlang/async@0.20.3`

Project-owned code prefers `moonbitlang/x` for filesystem and system helpers
and `moonbitlang/async` for asynchronous I/O. The pinned Google libraries still
depend transitively on `mizchi/x@0.5.2`; `moon.work` resolves those imports to
the vendored copy with the recorded native Windows compatibility patches.

Other MoonBit targets and other dependency versions are not part of the
validated Milestone 2 contract.

### Set up Project Authorization

Project Authorization is the default: an author grants access through the OAuth
identity of a Google Cloud project they select. Publishing, status, and logout
use the platform-native vault by default: macOS Keychain on Apple Silicon,
Secret Service on Linux x64, and Windows Credential Manager on Windows x64.
Interactive setup asks where to store credentials and recommends the native
vault when it is usable. Native-vault failure never falls back to a credential
file. On macOS, the native adapter uses the normal login Keychain model for a
standalone command-line tool; it does not require an app access-group
entitlement.

Run the guided flow from an interactive terminal:

```console
pumd auth setup
```

Before starting the Google flow, setup performs a write/read/delete capability
check using a separate, non-secret probe record. It shows both storage choices:
the native vault and the permission-hardened file store. An unusable native
vault remains visible but disabled with a specific explanation, such as a
locked service, an unsupported platform, or an unexpected macOS
missing-entitlement packaging result. The file option remains selectable with a
reduced-protection warning and is never selected by pressing Enter or as a
fallback. Enter `r` to recheck native-vault availability after unlocking or
repairing it without restarting setup.

Project provisioning happens in the browser, in Google-owned Cloud Console
flows. This avoids asking for a second, broad Cloud-management authorization
that would still leave consent settings and OAuth-client creation as manual
steps. `pumd` opens three flows and waits for the downloaded Desktop client JSON;
it never creates a project, enables an API, or mutates cloud state itself:

- **Enable the Docs API:**
  `https://console.cloud.google.com/flows/enableapi?apiid=docs.googleapis.com`
  handles Google sign-in, lets you select an existing project or create one,
  and enables `docs.googleapis.com`.
- **Enable the Drive API:**
  `https://console.cloud.google.com/flows/enableapi?apiid=drive.googleapis.com`
  enables `drive.googleapis.com` in the same project. `pumd` uses Drive only
  to inspect comments; it never uses Drive for Publication discovery.
- **Create the Desktop client:** `https://console.cloud.google.com/auth/clients`
  handles OAuth app registration when needed. Create a **Desktop app** client
  and download its JSON.

Google owns sign-in and account selection in these flows, so `pumd` no longer
lists accounts or projects in the terminal and no longer needs the Google
Cloud CLI.

For consent configuration, choose an audience that matches the account:

- **Workspace organization accounts:** publish the app as **Internal** when
  eligible. Internal apps do not need test users or verification.
- **Personal accounts:** **External** is the only option. In **Testing**, the
  `drive.file` refresh grant expires after seven days and the publishing
  account must be added as a test user; for durable personal use, move the app
  to **In production** when ready.
- `drive.file` is a non-sensitive scope, so full sensitive-scope verification
  is not required for it. Branding and app verification can have separate
  requirements, so follow any prompts the Console shows before selecting a
  production audience.

The direct OAuth flow accepts installed Desktop OAuth clients only and requests
exactly `drive.file`; enabling the Drive API for comment inspection does not
broaden that scope, and it requests no identity scopes.

If you have already downloaded the Desktop client JSON, skip the browser
provisioning steps and use the direct shortcut instead:

```console
pumd auth setup --client-file oauth-client.json
```

`oauth-client.json` is a Google Desktop OAuth client configuration. It is not a
user token, refresh credential, or service-account key. Interactive use prompts
for the credential store before `pumd` opens the direct installed-app OAuth
flow. If the native vault is disabled, follow its displayed remediation or
choose file storage deliberately.

`--credential-store=file` is the explicit reduced-protection alternative:

```console
pumd auth setup --client-file oauth-client.json --credential-store=file
pumd auth status --credential-store=file
pumd publish --auth=project --credential-store=file document.md
pumd auth logout --credential-store=file
```

After setup stores and validates the new authorization, it atomically remembers
only the non-secret `native` or `file` identifier. Bare publish, status, and
logout use that remembered choice; with no preference, they use native storage.
An explicit command option overrides the remembered store for that command.
Changing stores commits the new authorization and preference before removing
the previous local credential. A cleanup failure is reported and is never
presented as a completed single-credential migration.

Noninteractive setup never displays the selector. It honors an explicit store,
otherwise uses the remembered store, and otherwise attempts the native default.
It never changes to file storage because a native probe or write failed. To
bypass the interactive store menu while retaining native storage, select it
explicitly:

```console
pumd auth setup --credential-store=native
pumd auth setup --client-file oauth-client.json --credential-store=native
```

The default native-vault forms are:

```console
pumd auth status
pumd publish document.md
pumd auth logout
```

`auth status` reports the remembered or explicitly selected native/file store
type, usability or reauthorization state, and the Google Cloud project when the
downloaded client configuration provided it. `auth logout` removes local
credentials idempotently; it does not claim that Google's remote grant was
revoked. Refresh credentials obtain fresh access tokens as needed. A transient
refresh failure leaves the stored grant in place for retry; a revoked or invalid
grant requires setup again. Diagnostic and status output redact OAuth client
secrets, refresh credentials, access tokens, authorization codes, preference
contents beyond the store identifier, and native vault diagnostics.

Guided setup requires an interactive terminal. On a first interactive publish,
`pumd` offers guided setup only after source reading, rendering, validation, and
Desired Document planning succeed, and then resumes that publish when setup
succeeds. Declining performs no setup or remote mutation. Noninteractive publish
never prompts, opens a browser, or waits for an OAuth callback; run `auth setup`
deliberately or use one of the explicit automation routes below.

### Republishing, conflicts, and review safety

`pumd publish proposal.md` creates a Google Doc and local Publication the first
time. Later publishes use that Publication: pumd re-reads its Managed Tab,
compares the current Markdown and Google Docs content with the Published
Baseline, and applies only safe local changes. It does not discover or adopt
older documents, and it never replaces a missing, trashed, inaccessible,
read-only, or deleted Managed Tab. Other tabs and the document title after
creation remain untouched.

Reconciliation works on body paragraphs and whole tables, with text and
formatting both included. A local-only change is applied; a remote-only change
stays in Google Docs and is not imported into Markdown. Changes in separate
units can merge. If both sides changed the same unit, pumd stops with a
**Publication Conflict** instead of choosing a side. There is no force bypass.
Unsupported remote structures, such as images, section breaks, and footnotes,
are preserved as opaque remote-only content; pumd blocks rather than risking a
write when their alignment is ambiguous.

Every unresolved Google Docs comment is a **Review Barrier** for a
content-changing publish. Resolve the comments, then publish again. Resolved
comments do not block, and a publish with no content changes remains allowed.
Google Docs suggestions, including inserted/deleted text and style changes,
count as remote changes: disjoint suggestions survive, while an overlapping
local change becomes a Publication Conflict.

Before writing, pumd reads the document revision and includes it as
`writeControl.requiredRevisionId` in one atomic Docs batch. If the document
changes during that interval, Google rejects the batch and applies nothing;
re-read and retry. If a transport result is ambiguous, pumd re-reads the
Managed Tab to determine whether the intended state landed and never blindly
replays the write. A confirmed successful publish advances the Published
Baseline to the new Desired Document; a no-op publish leaves that baseline
unchanged.

Use `--dry-run` for either a new source or an existing Publication:

```console
pumd publish --dry-run proposal.md
```

It runs authorization, remote reading, comment inspection, normalization,
suggestion interpretation, and reconciliation, then reports planned structural
units, Publication Conflicts, Review Barriers, and concurrency-sensitive status.
It makes zero remote writes and zero Publication Registry changes.

### Explicit automation routes

ADC remains available only when explicitly selected:

```console
pumd publish --auth=adc document.md
```

This route uses authorized-user ADC; `pumd` requests `drive.file` and no
identity scopes. It does not fall back to Project Authorization, and Project
Authorization does not fall back to ADC. ADC is provisioned outside `pumd` and
may still use `gcloud`; `pumd` never invokes `gcloud`. Google's ADC flow
requires `cloud-platform` even when a client ID file is supplied, so provision
ADC with both scopes:

```console
gcloud auth application-default login \
  --client-id-file=oauth-client.json \
  --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/drive.file
```

This is an ADC/`gcloud` constraint, not a `pumd` requirement. See Google's
[ADC documentation](https://docs.cloud.google.com/docs/authentication/application-default-credentials#credentials_set_up_adc)
and [Drive/ADC example](https://docs.cloud.google.com/bigquery/docs/external-data-drive#authenticate_and_enable_drive_access).

For short-lived automation, pass an access token through the environment rather
than a command-line argument:

```console
PUMD_ACCESS_TOKEN="$(your-token-provider)" pumd publish --auth=token-env document.md
```

`pumd` reads this variable only after local preflight, never stores it, and never
tries another provider if it is missing or rejected. Avoid shell history and log
capture that could expose environment values. Managed Authorization remains a
future onboarding mode and is not selected by any current command.

### Publish a Markdown file with Project Authorization

After setup, publish with the default Project Authorization:

```console
pumd publish document.md
```

If setup remembered the explicit file store, the same bare publish command uses
it. Add `--credential-store=native|file` only to override the remembered choice
for one publish.

The first successful invocation creates a Google Doc and records its
Publication. Later invocations safely update the recorded Managed Tab rather
than creating another document. The document title is derived from the source
file name only at creation and is reviewer-owned afterward. Use
`pumd publish --dry-run document.md` to inspect the same create-or-update path
without writing.

On success, `pumd` prints this two-line result shape (with Google's real ID
substituted):

```text
document ID: 1AbCdEfGhIjKlMnOpQrStUvWxYz
edit URL: https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz/edit
```

Images are not supported yet. Both direct images such as
`![diagram](diagram.png)` and reference images produce a source-located
unsupported diagnostic. Source reading and decoding, rendering (including this
image check), and Desired Document planning all finish before authorization is
requested or any HTTP request is sent, so an image blocks publication before
credentials are read and before any remote document can be created or changed.

Ordered lists publish as native Google Docs lists when they start at `1`, with
either a period or parenthesis delimiter. Google Docs' create-bullets request
does not expose a writable starting number, so a Markdown list starting at any
other number fails Desired Document planning before authorization or HTTP instead of being
silently renumbered.

### Recover from publication failures

- For source access, decoding, rendering, or Desired Document planning errors,
  fix the local input and run the publish command again. These failures happen
  before credential access or remote mutation, so no Google Doc was created.
- For a Project Authorization authentication failure, run `pumd auth status`;
  then repeat setup with the same credential-store choice if reauthorization is
  required. For a locked native vault, unlock it and recheck. For permission
  denial, allow `pumd` or correct the platform policy; `pumd` does not fall back
  to a file. For a Google permission failure, confirm the exact `drive.file`
  scope and that both `docs.googleapis.com` and `drive.googleapis.com` are
  enabled in the selected project. For
  the explicit ADC route, recreate its ADC separately; neither route falls back
  to the other.
- If Google throttles a request, wait before trying again. For another explicit
  5xx response, wait and retry later; report other unexpected HTTP statuses
  before retrying.
- If document creation succeeded but population failed, the error includes the
  created document ID and edit URL. Inspect that document before deciding what
  to do next.
- If an update result is ambiguous, pumd re-reads before deciding whether the
  intended state landed. Do not assume a retry is safe until that diagnosis
  reports the current state.

Errors are classified without printing credential or access-token contents.

### Opt-in live integration test

The live smoke test is deliberately not part of the default test suite. Running
it **creates and leaves a real Google Doc in the authorized account's Drive**.
Run it only after deliberately configuring the authorization route being
tested. The MoonBit test publishes a mixed Markdown fixture through the live
Google Docs path, reads the resulting document back through the narrow Docs
adapter, verifies representative text and native structure, and prints the real
document URL:

```console
moon build --target native cmd/pumd
moon test --target native -p rainbowdashy/pumd/publish --include-skipped --filter "live smoke publishes and reads a real Google Doc"
```

Packaged Project Authorization smoke tests are opt-in for macOS arm64, Linux
x64, and Windows x64. Each uses that platform's native vault, replaces the
active Project Authorization twice to cover create and replacement, creates a
real Google Doc, then deletes the local authorization to cover logout. Run one
only with a dedicated account and project:

```console
PUMD_MACOS_PROJECT_AUTH_SMOKE=1 \
PUMD_MACOS_SMOKE_BINARY=/absolute/path/to/packaged/pumd \
PUMD_MACOS_SMOKE_CLIENT_FILE=/absolute/path/to/desktop-client.json \
moon test --target native -p rainbowdashy/pumd/publish \
  --include-skipped \
  --filter "macOS Apple Silicon packaged artifact smoke publishes with Project Authorization"
```

On Linux x64:

```console
PUMD_LINUX_PROJECT_AUTH_SMOKE=1 \
PUMD_LINUX_SMOKE_BINARY=/absolute/path/to/packaged/pumd \
PUMD_LINUX_SMOKE_CLIENT_FILE=/absolute/path/to/desktop-client.json \
moon test --target native -p rainbowdashy/pumd/publish \
  --include-skipped \
  --filter "Linux x64 packaged artifact smoke publishes with Project Authorization"
```

On Windows x64 PowerShell:

```powershell
$env:PUMD_WINDOWS_PROJECT_AUTH_SMOKE = "1"
$env:PUMD_WINDOWS_SMOKE_BINARY = "C:\path\to\pumd.exe"
$env:PUMD_WINDOWS_SMOKE_CLIENT_FILE = "C:\path\to\desktop-client.json"
moon test --target native -p rainbowdashy/pumd/publish `
  --include-skipped `
  --filter "Windows x64 packaged artifact smoke publishes with Project Authorization"
```

These live tests are never part of deterministic CI; ordinary CI requires no
browser, vault contents, Google credentials, network access, or live Cloud
project.

On success, its output includes lines with this form:

```text
REAL GOOGLE DOC CREATED: https://docs.google.com/document/d/REAL_DOCUMENT_ID/edit
Live smoke passed: https://docs.google.com/document/d/REAL_DOCUMENT_ID/edit
```

To validate only the MoonBit fixture's rendering and Google Docs update plan,
without credentials, network access, or a real Google Doc, run:

```console
moon test --target native -p rainbowdashy/pumd/publish --filter "live smoke fixture renders and plans locally"
```

## Version-one success criteria

Version one is successful when it can:

- Publish a Markdown file as a native Google Doc and return its stable URL.
- Republish to the same document without replacing unchanged content.
- Preserve comment anchors and reviewer formatting on unchanged paragraphs.
- Refuse conflicting local and remote edits by default.
- Refuse changes that would carelessly detach unresolved review feedback.
- Render headings, paragraphs, blockquotes, emphasis, links, lists, tables,
  inline code, and fenced code blocks with consistent native formatting.
- Support local and HTTPS images through a safe publishing workflow.
- Preview an incremental update without writing to Google.
- Recover cleanly from concurrency failures without corrupting local state.
- Request only the Google permissions needed for documents created or managed by
  the tool whenever the platform permits it.

## Product principles

- **Local-first:** Markdown and local publishing state are sufficient to resume
  work.
- **Native over simulated:** Prefer Google Docs structures over HTML/CSS import
  tricks.
- **Minimal writes:** Preserving an existing structure is better than rebuilding
  it.
- **Safe by default:** A blocked publish is better than lost review work.
- **Predictable over clever:** Stable formatting is more valuable than elaborate
  rendering that changes between documents.
- **Transparent:** Dry runs and conflict messages should describe intent in terms
  of document sections, not raw API indexes.
- **Escape hatches are explicit:** Force operations must be deliberate and
  narrowly scoped.

## Current implementation milestone

The first milestone is a pure MoonBit library that parses Markdown with a
`pumd`-owned fork of `mizchi/markdown` and renders its CST into a deterministic,
Google-Docs-native `DesiredDocument`. It includes explicit, source-located
errors for parsed constructs without a rendering rule and golden tests for the
desired native structure.

The supported rendering set is headings, paragraphs, emphasis, links, lists,
tables, inline code, fenced code blocks, and blockquotes. Blockquote rendering
supports `>` syntax, nesting, lazy continuation, and paragraphs, headings,
lists, and fenced code blocks inside a blockquote, including quote/list
composition. Tables remain supported generally, but a table inside a blockquote
is unsupported. Parser-supported constructs outside that set do not gain
implicit behavior; they produce an unsupported-construct error until an
explicit native rendering rule is added. Image rendering is deferred: direct
images and reference images currently yield source-located unsupported
diagnostics.

Rendering applies one versioned, built-in style profile with opinionated defaults
for body text and every supported document element. Configurable themes and
templates are outside this milestone.

The publishing milestone adds the native `pumd publish <markdown-path>` command.
It reads and decodes the source, creates and records a Publication when
unlinked, and safely reconciles updates to the recorded Managed Tab when linked.
It uses the Published Baseline to preserve remote-only work and block
Publication Conflicts or Review Barriers rather than overwriting review work.

## Non-goals

The initial product will not attempt to:

- Implement a browser-grade CSS engine inside Google Docs.
- Reproduce arbitrary web layouts pixel-for-pixel.
- Make Google Docs a lossless general-purpose Markdown editor.
- Silently merge simultaneous edits to the same content.
- Preserve arbitrary manual edits inside content that the author explicitly
  changed locally.
- Provide syntax highlighting by default.
- Replace Google Docs as the review interface.
- Synchronize every file in Google Drive or provide a general Google Workspace
  CLI.

## Deliberately unresolved

These decisions should follow from the goals rather than be fixed prematurely:

- Exact command names beyond the core publish workflow.
- Stable unit-matching strategy within three-way reconciliation.
- Whether custom templates belong in version one.
- How suggestions are surfaced or reconciled after reviewers finish.
