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
Headings, paragraphs, lists, links, tables, images, inline code, and fenced code
blocks should have consistent native Google Docs formatting. Fenced code must
remain editable and commentable, with a legible monospaced presentation.

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

- `mizchi/x@0.5.2` (resolved to the vendored workspace copy, with the recorded
  native Windows compatibility patches)
- `ryota0624/googleauth@0.2.0`
- `ryota0624/googleapis@0.4.1`
- `moonbitlang/async@0.20.3`

Other MoonBit targets and other dependency versions are not part of the
validated Milestone 2 contract.

### Enable Google Docs and configure authorized-user ADC

1. Create or select a Google Cloud project and enable the **Google Docs API**.
   With the Google Cloud CLI, the enablement command is:

   ```console
   gcloud services enable docs.googleapis.com --project=YOUR_PROJECT_ID
   ```

2. Configure the project's OAuth consent screen. If the app is in testing,
   include the Google account that will publish as a test user.
3. Create an OAuth client ID with application type **Desktop app**, then download
   its client JSON as `oauth-client.json`.
4. Use that client only to create authorized-user Application Default
   Credentials (ADC), requesting the required `drive.file` scope:

   ```console
   gcloud auth application-default login --client-id-file=oauth-client.json --scopes=https://www.googleapis.com/auth/drive.file
   ```

`oauth-client.json` is the Desktop client definition; it is not itself ADC.
The command above writes an `authorized_user` ADC file. `pumd` uses the
authorized-user refresh token from that file and requires exactly this scope:
`https://www.googleapis.com/auth/drive.file`.

For the normal local setup, leave `GOOGLE_APPLICATION_CREDENTIALS` unset and
`pumd` will look for the gcloud ADC file at `$HOME/.config/gcloud/application_default_credentials.json`,
or at `%APPDATA%\gcloud\application_default_credentials.json` when `HOME` is not
set. If `GOOGLE_APPLICATION_CREDENTIALS` is set, the pinned auth library checks
that path first. It may point to a valid `authorized_user` ADC JSON file, but it
must not point to `oauth-client.json`. An unreadable, invalid, or unsupported
file at the override path is ignored and discovery continues at the well-known
location. A valid service-account JSON is detected differently: the library
selects it, but its service-account token exchange is not implemented in the
pinned version, so publication fails instead of falling back. Service-account
credentials are therefore not supported by the current publisher. Unset a
stale or confusing override to use the gcloud authorized-user ADC file.

### Publish a Markdown file

From the repository root, the exact Milestone 2 publish command is:

```console
moon run --target native cmd/pumd -- publish proposal.md
```

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
image check), and Desired Document planning all finish before ADC is requested
or any HTTP request is sent, so an image blocks publication before credentials
are read and before any remote document can be created or changed.

Ordered lists publish as native Google Docs lists when they start at `1`, with
either a period or parenthesis delimiter. Google Docs' create-bullets request
does not expose a writable starting number, so a Markdown list starting at any
other number fails Desired Document planning before ADC or HTTP instead of being
silently renumbered.

### Recover from publication failures

- For source access, decoding, rendering, or Desired Document planning errors,
  fix the local input and run the publish command again. These failures happen
  before credential access or remote mutation, so no Google Doc was created.
- Authentication errors distinguish unavailable, invalid, unrefreshable, and
  Google-rejected ADC. Re-run the authorized-user ADC command above. For a
  permission failure, confirm that ADC was minted with the exact `drive.file`
  scope and that the Google Docs API is enabled in the OAuth client's project.
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
it **creates and leaves a real Google Doc in the authenticated account's
Drive**. The MoonBit test publishes a mixed Markdown fixture through the
production ADC and Google Docs path, reads the resulting document back through
the narrow Docs adapter, verifies representative text and native structure, and
prints the real document URL:

```console
moon build --target native cmd/pumd
moon test --target native -p rainbowdashy/pumd/publish --include-skipped --filter "live smoke publishes and reads a real Google Doc"
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
- Render headings, paragraphs, emphasis, links, lists, tables, inline code, and
  fenced code blocks with consistent native formatting.
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

The first milestone is a pure MoonBit library that parses Markdown with
`mizchi/markdown` and renders its CST into a deterministic, Google-Docs-native
`DesiredDocument`. It includes explicit, source-located errors for parsed
constructs without a rendering rule and golden tests for the desired native
structure.

The supported rendering set is headings, paragraphs, emphasis, links, lists,
tables, inline code, and fenced code blocks. Parser-supported constructs outside
that set do not gain implicit behavior; they produce an unsupported-construct
error until an explicit native rendering rule is added. Image rendering is
deferred: direct images and reference images currently yield source-located
unsupported diagnostics.

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

- Distribution format.
- Exact command names beyond the core publish workflow.
- Local state-file layout and stable block identity strategy.
- Whether custom templates belong in version one.
- The policy for accepting remote-only edits back into local Markdown.
- How suggestions are surfaced or reconciled after reviewers finish.
