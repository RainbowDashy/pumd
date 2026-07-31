# pumd

`pumd` publishes local Markdown as a native Google Doc that is pleasant to read,
edit, comment on, and review.

The local Markdown file remains the authoritative source. Publishing it again
should update the existing Google Doc safely and incrementally instead of
replacing the entire document.

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

### Run the native command from a checkout

First create a Desktop OAuth client, download its JSON, and configure
Application Default Credentials with the narrow `drive.file` scope:

```console
gcloud auth application-default login --client-id-file=oauth-client.json --scopes=https://www.googleapis.com/auth/drive.file
```

Then publish one Markdown file:

```console
moon run cmd/pumd -- publish proposal.md
```

The command validates and decodes the source before it obtains credentials or
makes an HTTP request. On success it prints the new document ID and canonical
edit URL. Unsupported Markdown and failures at source access, authentication,
creation, population, or response decoding are reported with their stage.

An opt-in smoke script creates a temporary comprehensive Markdown fixture,
publishes it through the actual native `pumd publish <path>` command, captures
the document ID and edit URL printed by that process, then reads back that same
Google Doc. It requires ADC and writes to Google:

```console
powershell -ExecutionPolicy Bypass -File scripts/live-smoke.ps1
```

### Make every write inspectable

Authors should be able to preview what would change before publishing. Results
and failures should explain which Markdown sections are affected and why a push
is safe, blocked, or requires intervention.

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

The current publishing slice adds a native `pumd publish <markdown-path>`
command. It reads and decodes the source, derives the Google Doc title from the
file name, then uses Application Default Credentials to create and populate one
new Google Doc. Every invocation creates a new document. Incremental updates,
local publishing state, diffing, and remote reconciliation remain deferred.

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
