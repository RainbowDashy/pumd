# Managing published Google Docs

Research date: 2026-08-05

## Conclusion

`pumd` can update and list its documents without broadening its existing
`drive.file` OAuth grant. The selected product model is:

1. Keep one machine-local Publication Registry in pumd's user-level platform
   configuration directory. It maps each canonical absolute Markdown source
   path to the Google document created by this installation and its Published
   Baseline.
2. Make `pumd list` enumerate that local registry; it does not search Drive or
   discover Publications owned by another installation.
3. Update content with a read/plan/compare-and-swap cycle: Docs
   `documents.get`, reconciliation against the Desired Document, then one
   `documents.batchUpdate` carrying `writeControl.requiredRevisionId`.
4. Keep `drive.file`. Enable the Drive API only to inspect unresolved comments;
   it is not used for publication discovery.

The Google Doc remains an ordinary collaborative review surface. Only pumd's
Publication Registry is deliberately local: losing that state loses the
create-or-update relationship, and another installation does not inherit it.

## Current repository state

The implementation now has a machine-local Publication Registry keyed by
canonical source path. Each Publication records the Google document ID, Managed
Tab ID, and Published Baseline, so `pumd publish` is create-or-update rather
than create-only. First publish creates and registers the destination; later
publishes re-read only that Managed Tab and never discover or replace a legacy
document.

The update path reads tab-aware Google Docs content with
`includeTabsContent=true` and `suggestionsViewMode=SUGGESTIONS_INLINE`, then
normalizes the remote document and reconciles it with the local Desired Document
and Published Baseline. It treats body paragraphs and whole tables as units,
including text and formatting, preserves remote-only units, and lowers
non-conflicting local changes into minimal ordered requests. Unsupported remote
structures remain opaque remote-only units; ambiguous alignment becomes a
Publication Conflict. Inline suggestions participate as remote changes.

Before any content-changing update, pumd paginates Drive comment inspection.
An unresolved comment is a Review Barrier; a no-op inspection is allowed. A
write uses one atomic Docs batch with `writeControl.requiredRevisionId` from the
read. A revision conflict applies nothing, and an ambiguous transport outcome
is recovered by re-reading before pumd decides whether the intended state
landed. Confirmed success atomically advances the Published Baseline to the new
Desired Document; a no-op does not.

`publish --dry-run` executes authorization, remote reading, comment inspection,
normalization, suggestion interpretation, and reconciliation, and reports its
planned units, Publication Conflicts, Review Barriers, and concurrency-sensitive
status without remote writes or Publication Registry changes. `pumd list` is
local by default, while `pumd list --refresh` explicitly inspects registered
documents; `pumd move` and `pumd forget` manage only local Publication records.

Project Authorization still requests exactly
`https://www.googleapis.com/auth/drive.file`, with no identity scopes. Its
browser handoff now requires enabling `docs.googleapis.com` first and
`drive.googleapis.com` second before creating the Desktop client. Drive is used
only for comment inspection, never Publication discovery.

## Rejected remote identity and tagging alternative

Use Drive v3 `appProperties`, not the document title, as the remote ownership
marker. Titles are not unique; `appProperties` are private to the requesting
app and are directly searchable. Public `properties` are visible to every app
with access to the file, so they should be used only if cross-application
portability is an explicit product requirement
([custom-property guide](https://developers.google.com/workspace/drive/api/guides/properties),
[File resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files#File.FIELDS.properties)).

Suggested initial schema:

```json
{
  "appProperties": {
    "pumd.managed": "1",
    "pumd.schema": "1",
    "pumd.publicationId": "<stable locally generated publication UUID>",
    "pumd.desiredHash": "<SHA-256 of canonical Desired Document>"
  }
}
```

Do not put an absolute local path in Drive metadata: it leaks machine details
and is not stable across checkouts. Store the UUID-to-path/document-ID mapping
locally. The desired hash is useful for drift detection but is not a Published
Baseline; preserving user edits requires a stored prior Desired Document or a
structural reconciliation strategy.

If creation remains on the Docs API, tag the file after successful first
population with:

```http
PATCH https://www.googleapis.com/drive/v3/files/{documentId}?supportsAllDrives=true&fields=id,name,modifiedTime,webViewLink,appProperties,version
Content-Type: application/json

{"appProperties":{"pumd.managed":"1","pumd.schema":"1","pumd.publicationId":"...","pumd.desiredHash":"..."}}
```

`files.update` has patch semantics and accepts `drive.file`; null map entries
clear individual properties
([files.update](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update),
[File fields](https://developers.google.com/workspace/drive/api/reference/rest/v3/files#File.FIELDS.app_properties)).
The Docs create endpoint cannot carry this metadata: it creates a blank
document from the title and ignores other supplied fields
([documents.create](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/create)).
Tagging is therefore a separate Drive request unless creation is later moved to
Drive `files.create`. Moving creation to `files.create` with the Google Docs
MIME type and initial `appProperties` is preferable: it stamps the publication
UUID in the same request that creates the file. A lifecycle property such as
`pumd.state=creating|ready` can then make interrupted population visible and
recoverable instead of leaving an indistinguishable blank document.

Google limits a file to 100 custom properties total, 30 public properties
total, 30 private properties per app, and 124 UTF-8 bytes for each combined
key/value pair. The schema above fits those limits
([custom-property limits](https://developers.google.com/workspace/drive/api/guides/properties#limits_of_custom_file_properties)).

Private metadata is a deliberate tradeoff. Google defines `appProperties` as
private to the requesting app and retrievable with a token obtained through an
OAuth client ID. It follows that credentials from unrelated OAuth clients must
be treated as separate private-property namespaces; the official docs do not
promise portability between them. Public `properties` would make the marker
visible across apps, but would not by itself overcome `drive.file` access to
the underlying file.

## Rejected Drive-backed listing alternative

Use Drive `files.list`:

```http
GET https://www.googleapis.com/drive/v3/files
  ?spaces=drive
  &corpora=user
  &q=trashed%20%3D%20false%20and%20mimeType%20%3D%20'application%2Fvnd.google-apps.document'%20and%20appProperties%20has%20%7B%20key%3D'pumd.managed'%20and%20value%3D'1'%20%7D
  &orderBy=modifiedTime%20desc
  &pageSize=1000
  &fields=nextPageToken,incompleteSearch,files(id,name,createdTime,modifiedTime,webViewLink,version,appProperties,capabilities(canEdit,canModifyContent))
```

The unencoded `q` is:

```text
trashed = false and
mimeType = 'application/vnd.google-apps.document' and
appProperties has { key='pumd.managed' and value='1' }
```

Drive officially supports the `appProperties has { key=... and value=... }`
form. `has` is exact key/value matching; it is not a prefix scan. Query strings
must escape apostrophes/backslashes and then be URL-encoded
([search examples](https://developers.google.com/workspace/drive/api/guides/search-files#query_string_examples),
[query terms/operators](https://developers.google.com/workspace/drive/api/guides/ref-search-terms)).
Explicitly request fields because `files.list` otherwise returns only a small
default projection. Add `trashed = false` because the method includes trashed
files by default. Follow `nextPageToken`; without `orderBy`, order is arbitrary
([files.list](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list)).

For shared-drive support, send `supportsAllDrives=true` and
`includeItemsFromAllDrives=true`. Prefer `corpora=user` for the normal case or
enumerate a specific shared drive with `corpora=drive&driveId=...`. A broad
`corpora=allDrives` search can return `incompleteSearch=true`, which must be
surfaced or retried against narrower corpora
([corpora and pagination](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list#query-parameters)).

Existing Google Docs absent from the local Publication Registry are outside
this management model. There is no legacy adoption or title-based inference.

## Updating a document in place

Recommended request sequence:

1. Resolve the document ID and Managed Tab ID from the local Publication
   Registry.
2. Read the current document with
   `GET https://docs.googleapis.com/v1/documents/{documentId}?includeTabsContent=true&suggestionsViewMode=SUGGESTIONS_INLINE`.
   This returns the latest document, including its opaque `revisionId`; tab
   content is otherwise omitted or represented only through legacy first-tab
   fields
   ([documents.get](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/get),
   [Document resource](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents#Document.FIELDS.revision_id)).
3. Normalize the remote native structure and compare it with the new Desired
   Document. The repository already chose this seam: render desired state
   independently, then reconcile remote structure into ordered update requests
   ([ADR-0002](../adr/0002-render-to-a-desired-document.md)).
4. Submit one batch:

   ```json
   {
     "requests": ["<reconciliation requests>"],
     "writeControl": {"requiredRevisionId": "<revisionId from get>"}
   }
   ```

   to `POST https://docs.googleapis.com/v1/documents/{documentId}:batchUpdate`.
5. On success, atomically commit the new Desired Document as the Published
   Baseline. The Google Doc title is derived from the source only at creation
   and is reviewer-owned afterward.

### Reconciliation choices

- **Authoritative whole-body replacement (rejected).** Read the
  managed tab, delete its existing body content while retaining the mandatory
  final newline, then replay the existing plan from index 1. For a simple body,
  the delete range is `[1, bodyEndIndex - 1)`. The compiler must include whole
  tables/structural elements: Docs rejects deletion of the final newline,
  partial surrogate pairs, partial tables, and other structurally invalid
  ranges
  ([DeleteContentRangeRequest](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/request#DeleteContentRangeRequest)).
  This is deterministic but overwrites manual edits and can disturb anchors,
  bookmarks, named ranges, or other structures attached to deleted content. If
  no trusted Published Baseline exists, do not update the document.
- **Structural minimal reconciliation (selected).** Decode the
  remote document into the same native vocabulary, compare it with the Desired
  Document, and emit minimal deletes/inserts/style changes. This aligns with
  ADR-0002 and reduces churn, but it still needs an explicit policy for edits
  made only in Google Docs and a Published Baseline for true three-way
  reconciliation.
- **Managed named range (optional boundary, not a full solution).** Named
  ranges track inserted content and can split as the document changes, but are
  visible to all apps/collaborators. `replaceNamedRangeContent` accepts plain
  text only, so rich `pumd` output still needs normal delete/insert/style
  requests
  ([NamedRange](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents#NamedRange),
  [ReplaceNamedRangeContentRequest](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/request#ReplaceNamedRangeContentRequest)).

The update implementation must be tab-aware. Each Publication records exactly
one Managed Tab ID established by first publish. All other tabs remain
untouched; deleting the Managed Tab produces `remote-missing` and never causes
pumd to switch tabs or recreate it. With `includeTabsContent=false`, legacy
fields describe only the first tab, and many mutation locations default to the
first tab when `tabId` is omitted, so every managed read and write must identify
the recorded tab explicitly.

Remote structures outside the Desired Document vocabulary are retained as
opaque remote-only units when their boundaries can be separated from local
changes. If safe alignment is ambiguous, they produce a Publication Conflict;
pumd never deletes an unsupported remote structure merely because Markdown
cannot represent it.

## Proposed command behavior

Keep `publish` as the single everyday create-or-update operation:

```console
pumd publish proposal.md  # creates when unlinked; safely updates when linked
pumd publish --dry-run proposal.md  # reads and reports without writing
pumd list                 # lists this installation's Publication Registry
pumd list --json          # stable automation output
pumd list --refresh       # explicitly inspects registered remote documents
pumd move old.md new.md   # re-associates a renamed local source
pumd forget proposal.md   # removes only the local relationship
```

A separate `update` command would make authors choose an implementation state
that `pumd` can resolve from its Publication Registry. Plain `list` is offline
and reports the local source path, document ID/URL, last successful publish,
and local status. `list --refresh` explicitly contacts only registered
documents to add the current remote title, editability, and availability; it
never discovers unknown documents.

Each canonical source path has at most one active Publication. A first publish
creates it; every later publish updates the associated document rather than
creating or selecting another destination. Renaming a source requires an
explicit local `move`; pumd does not infer identity from matching content.
Missing sources remain listed with a `missing-source` status until explicitly
forgotten. Forgetting leaves the Google Doc untouched.
Missing, trashed, or inaccessible remote documents also remain registered;
`publish` reports their status and never creates a replacement automatically.

The local record needs more than the document ID: store a schema version,
canonical absolute source path, document ID, managed tab ID, and the Published
Baseline. A hash alone can detect equality but cannot explain or reconcile
local-versus-remote changes.

Registry replacement is atomic and fail-closed: malformed or unsupported state
is preserved for diagnosis and blocks mutation rather than being reset. First
publish verifies registry writability before authorization, records a
provisional entry as soon as document creation returns an ID, and commits the
Published Baseline only after population is confirmed. Population retries
therefore reuse the known document. An ambiguous creation with no returned ID
records a blocked local state so retry cannot silently create a duplicate; the
user must inspect Drive and explicitly forget that state before trying again.
Because the registry contains the full Published Baseline, not only hashes, its
file and temporary replacements use owner-only permissions. Local mutation
commands hold one process-level registry lock through their operation; this
personal CLI deliberately serializes publishes rather than risking concurrent
registry loss or two updates to the same Publication.

`publish --dry-run` performs the same authorization, remote reads, comment
inspection, and reconciliation as publish, but never creates a document,
submits a batch, or changes the Publication Registry. For an unpublished source
it reports the planned creation without reserving a Publication.

Version one reconciles body paragraphs independently and treats each whole
table as one unit. Text and formatting both count: if Markdown and Google Docs
change the same unit relative to the Published Baseline, the complete publish
is blocked even if different words or cells changed. Changes in distinct units
may be merged.

## Comments and suggestions

Stable Drive `comments.list` can enumerate unresolved comments with
`drive.file`, but Drive comment anchors cannot reliably locate those comments
within the current Google Docs structure: Google says an anchor's position
relative to content is not guaranteed between revisions
([comments.list](https://developers.google.com/workspace/drive/api/reference/rest/v3/comments/list),
[comment anchor constraints](https://developers.google.com/workspace/drive/api/guides/manage-comments#comment_constraints)).
Exact Docs comment ranges are currently a Developer Preview feature, so version
one does not depend on them.

Consequently, any unresolved comment is a Review Barrier: no-op inspection is
allowed, but every content-changing publish is blocked until all comments are
resolved. This requires enabling `drive.googleapis.com`, but no broader OAuth
scope. Suggestions are represented inline by the stable Docs read model; their
text and style ranges participate in the normal paragraph/table conflict rule
([Docs suggestions](https://developers.google.com/workspace/docs/api/how-tos/suggestions)).

## Concurrency and failure safety

Use `requiredRevisionId` for normal publishing. If the document changed after
the read, Google rejects the batch with HTTP 400 and applies nothing. This is
the correct behavior for an authoritative renderer: re-read, report drift, and
reconcile again. `targetRevisionId` instead asks Docs to transform the batch
against collaborator changes; it can preserve both sets of edits, but conflict
resolution is server-defined and stale target IDs are rejected. It is better
suited to fine-grained collaborative edits than whole-body replacement
([WriteControl](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/batchUpdate#WriteControl)).

A Docs `revisionId` is opaque, user-specific, and guaranteed valid for only 24
hours, so it is a short-lived compare-and-swap token, not durable publication
metadata. Drive's `headRevisionId` is only available for binary Drive files,
not Google Docs; Drive's monotonic `version` is useful for display/drift hints
but is not the Docs write precondition
([Document revision ID](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents#Document.FIELDS.revision_id),
[Drive revision/version fields](https://developers.google.com/workspace/drive/api/reference/rest/v3/files#File.FIELDS.head_revision_id)).

All requests inside one Docs batch are validated and applied atomically. If a
batch transport result is ambiguous, retrying the identical batch with the same
`requiredRevisionId` is safe to diagnose: a prior success changed the revision
and makes the replay fail; then re-read and compare with desired state. Google
guarantees atomicity only within `documents.batchUpdate`
([batchUpdate guarantees](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/batchUpdate)).

After a successful disjoint merge, the new Desired Document—not the merged
remote result—becomes the Published Baseline. Preserved remote-only edits remain
visible as remote divergence on later publishes. A no-op publish never absorbs
them into the baseline.

## OAuth implications of the rejected remote alternative

No new OAuth scope is needed. Docs `get`, `create`, and `batchUpdate`, and Drive
`files.list`, `files.update`, and `files.create`, all accept `drive.file`. Google
describes it as the recommended non-sensitive scope for specific files the app
creates, opens, or the user shares with it
([Docs scopes](https://developers.google.com/workspace/docs/api/auth),
[Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)).

Consequences:

- `pumd list` must use the same auth selector as publish and describe its result
  as belonging to that authorization identity. Project, ADC, and arbitrary
  token-env credentials can expose disjoint sets.
- Replacing an OAuth client can strand remote private markers and per-file
  authorization. A local ID preserves identity but does not grant the new app
  access; reacquisition requires an app open/picker flow or another explicit
  authorization mechanism.
- Adding `drive.metadata.readonly` would broaden listing to account metadata but
  is a restricted scope and still would not grant content updates. It is not
  justified for managing files created by the current app.
- Remote discovery would not require a broader scope, but it was rejected. The
  selected design still enables both Docs and Drive APIs solely because stable
  comment inspection uses Drive.

## Recommended delivery order

**Status: implemented.** The sequence remains below as the delivery record for
the completed create-or-update behavior.

1. Define and atomically persist the user-level, machine-local Publication
   Registry keyed by canonical absolute source path.
2. Make first publish commit its document ID and prior Desired Document to the
   registry, with explicit recovery for interrupted or ambiguous creation.
3. Add offline `list` over local registry entries and an explicit `--refresh`
   that inspects only their current Google Docs state.
4. Add paginated Drive comment inspection and the unresolved-comment Review
   Barrier.
5. Decode the remote Docs read model, including inline suggestions, and add
   no-op/drift/conflict reporting without writing.
6. Compile non-conflicting structural differences into minimal,
   revision-checked updates. Version one has no force bypass for Publication
   Conflicts or Review Barriers and never uses whole-body replacement.
