# pumd

`pumd` publishes local Markdown as a native Google Doc that is pleasant to read,
edit, comment on, and review.

The local Markdown file remains the authoritative source. Publishing it again
should update the existing Google Doc safely and incrementally instead of
replacing the entire document.

> **Current Milestone 2 behavior:** `pumd` can create and populate a native
> Google Doc, but it does not republish to an existing document. Every publish
> creates a new document. Stable republishing, diffing, and remote
> reconciliation are version-one goals that remain deferred.

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

The current publishing milestone creates a new document for every invocation;
safe incremental updates are a later milestone. Google document IDs, tab IDs,
UTF-16 indexes, named ranges, and request ordering are implementation concerns
that the author should not need to manage.

### Make every write inspectable

Authors should be able to preview what would change before publishing. Results
and failures should explain which Markdown sections are affected and why a push
is safe, blocked, or requires intervention.

## Current Milestone 2 setup and publishing

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

Project Authorization is an opt-in authorization mode in this milestone: an
author grants access through the OAuth identity of a Google Cloud project they
select. It is currently supported by the native Apple-Silicon macOS build and
defaults to the macOS Keychain for its durable authorization document.

Run the guided flow from an interactive terminal:

```console
pumd auth setup
```

The guide requires the Google Cloud CLI. Install `gcloud` if prompted, then
sign in before retrying:

```console
gcloud auth login
```

It lists the Google accounts known to `gcloud`, preselects an active account
when it is available, and then lists its Cloud projects. Selecting an existing,
available project is the default path; creating a new project is an explicit
optional choice. Before it creates a project or enables an API, `pumd` previews
the precise mutation and asks for confirmation. Answering anything other than
yes cancels before that requested cloud change. Guided setup enables only
`docs.googleapis.com` (the Google Docs API); it does not enable a bundle of
Google APIs.

Google does not allow `pumd` to manage OAuth consent settings or OAuth clients
programmatically. The guide therefore previews and hands off the following
steps to Google Cloud Console; it never overwrites an existing, conflicting, or
unknown configuration:

- **Branding:** `https://console.cloud.google.com/auth/branding?project=PROJECT_ID`
- **Audience:** `https://console.cloud.google.com/auth/audience?project=PROJECT_ID`
- **Data Access / scopes:** `https://console.cloud.google.com/auth/scopes?project=PROJECT_ID`
- **OAuth clients:** `https://console.cloud.google.com/auth/clients?project=PROJECT_ID`

In the Console, create the minimum External/testing consent configuration, add
the publishing account as a test user when required, configure only
`https://www.googleapis.com/auth/drive.file`, and create a **Desktop app**
client. Download that installed-client JSON when prompted. The direct OAuth
flow accepts installed Desktop OAuth clients only and requests exactly
`drive.file`; it requests no identity scopes.

If you have already downloaded the Desktop client JSON, skip the project guide
and use the direct shortcut instead:

```console
pumd auth setup --client-file oauth-client.json
```

The client JSON is a client definition, not a refresh credential. `pumd` opens
the direct installed-app OAuth flow, then stores the resulting authorization in
the macOS Keychain. It never silently falls back to a file. If macOS denies
Keychain access or the login Keychain is unavailable, unlock it and allow
access, then retry; choose file storage only deliberately.

`--credential-store=file` is the explicit reduced-protection alternative. Use
the same store selection consistently for setup, status, publishing, and
logout:

```console
pumd auth setup --client-file oauth-client.json --credential-store=file
pumd auth status --credential-store=file
pumd publish --auth=project --credential-store=file document.md
pumd auth logout --credential-store=file
```

The default Keychain forms are:

```console
pumd auth status
pumd publish --auth=project document.md
pumd auth logout
```

`auth status` checks whether the selected stored authorization is usable;
`auth logout` removes it (and is harmless when it is already absent). Refresh
credentials obtain fresh access tokens as needed. If refresh fails, consent or
scope changed, or the credential was revoked, run setup again with the same
credential-store choice. Diagnostic and status output redact OAuth client
secrets, refresh credentials, and access tokens.

Guided setup requires an interactive terminal. In noninteractive environments,
use a previously configured Desktop client through `--client-file <path>` when
that OAuth interaction is appropriate, or supply explicit automation
credentials through the ADC route below; the guide does not infer a credential
store or silently switch authorization modes.

### Explicit ADC route (transition only)

ADC remains available as an explicitly selectable route:

```console
pumd publish --auth=adc document.md
```

This route continues to use authorized-user ADC with exactly the `drive.file`
scope and no identity scopes. It does not fall back to Project Authorization,
and Project Authorization does not fall back to ADC. The global default has not
changed yet: omitting `--auth` still selects ADC during this transition.

### Publish a Markdown file with Project Authorization

After setup, the explicit Project Authorization publish command is:

```console
pumd publish --auth=project document.md
```

For the explicit file store, add `--credential-store=file` as shown above.

Each successful invocation creates a new Google Doc, including when the same
Markdown file was published before. The document title is the source file name
without its final extension. Republish-to-the-same-document, local publication
state, diffing, conflict detection, and remote reconciliation are deferred.

On success, `pumd` prints this two-line result shape (with Google's real ID
substituted):

```text
document ID: 1AbCdEfGhIjKlMnOpQrStUvWxYz
edit URL: https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz/edit
```

Images are not supported in Milestone 2. Both direct images such as
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
  required. For a Keychain denial, unlock the login Keychain and allow access;
  `pumd` does not fall back to a file. For a permission failure, confirm the
  exact `drive.file` scope and that `docs.googleapis.com` is enabled in the
  selected project. For the explicit ADC route, recreate its ADC separately;
  neither route falls back to the other.
- If Google throttles a request, wait before trying again. For another explicit
  5xx response, wait and retry later; report other unexpected HTTP statuses
  before retrying.
- If document creation succeeded but population failed, the error includes the
  created document ID and edit URL. Inspect that document before deciding what
  to do next.
- A transport or response-decoding failure can be ambiguous: the remote mutation
  may have succeeded. `pumd` does not retry automatically. Inspect Google Drive
  and any reported document before retrying, because every retry creates another
  new document.

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

The packaged macOS Project Authorization smoke is also opt-in. It performs
setup with the supplied Desktop client, replaces the active authorization in
the default Keychain, and creates a real Google Doc. Run it only from Apple
Silicon macOS with a dedicated account and project:

```console
PUMD_MACOS_PROJECT_AUTH_SMOKE=1 \
PUMD_MACOS_SMOKE_BINARY=/absolute/path/to/packaged/pumd \
PUMD_MACOS_SMOKE_CLIENT_FILE=/absolute/path/to/desktop-client.json \
moon test --target native -p rainbowdashy/pumd/publish \
  --include-skipped \
  --filter "macOS Apple Silicon packaged artifact smoke publishes with Project Authorization"
```

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

Milestone 2 adds the native `pumd publish <markdown-path>` command. It reads and
decodes the source, derives the Google Doc title from the file name, then uses
authorized-user Application Default Credentials to create and populate one new
Google Doc. Every invocation creates a new document. Incremental updates, local
publishing state, diffing, and remote reconciliation remain deferred.

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
- Local state-file layout and stable block identity strategy.
- Whether custom templates belong in version one.
- The policy for accepting remote-only edits back into local Markdown.
- How suggestions are surfaced or reconciled after reviewers finish.
