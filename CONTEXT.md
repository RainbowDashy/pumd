# Markdown Publishing

The language used to describe how a local Markdown document becomes and remains an editable native document on a publishing platform.

## Language

**Desired Document**:
The complete Google-Docs-native structure that publishing intends to produce from the current Markdown source, independent of any document currently stored remotely. It is expressed as native elements such as paragraphs, text runs, bullets, tables, and inline objects rather than Markdown constructs; source provenance may be attached as metadata but is not part of the native content.
_Avoid_: Document IR, request plan, API document

**Style Profile**:
The coherent set of native formatting defaults that publishing applies to body text and supported document elements. Version one has one built-in profile.
_Avoid_: Stylesheet, theme, template

**Style Migration**:
A native-formatting change caused by a new version of the built-in Style Profile, even when the Markdown source is unchanged. A Publication applies a Style Migration through its normal safe update flow on the next publish.
_Avoid_: Theme upgrade, forced restyle

**Syntax Highlighting**:
Token-level foreground coloring applied to a fenced code block when its explicit language tag names a supported language. It is native editable text formatting within the code block, not embedded markup or an image.
_Avoid_: Code rendering, language detection, colored code image

**Blockquote**:
A quoted block of Markdown content introduced by the `>` marker and published as visibly distinct native document content.
_Avoid_: Backquote, backquote block marker

**Managed Authorization**:
An author's grant of Google access through the OAuth identity owned and operated by `pumd`. It is a future authorization mode intended to remove user-owned Google Cloud setup.
_Avoid_: Default ADC, built-in credentials

**Project Authorization**:
An author's grant of Google access through the OAuth identity owned by a user-selected Google Cloud project. It is the default authorization and provides independent consent configuration and quota ownership.
_Avoid_: BYO client, custom credentials

**Publication**:
The single active relationship, owned by one local `pumd` installation, between a Markdown source and the Google Doc that installation created and may update.
_Avoid_: Remote document, shared publication

**Pull**:
An explicit operation that incorporates committed, Markdown-representable changes from a Publication's Managed Tab into its local Markdown source. It rewrites only affected structural units as canonical Markdown, leaves untouched source bytes unchanged, and begins a Pending Merge when changes overlap.
_Avoid_: Bidirectional publish, automatic download, import

**Source Semantics**:
Document meaning representable in Markdown, such as headings, emphasis, links, lists, and tables. Cosmetic Google Docs formatting such as fonts, colors, and spacing is reviewer-owned presentation rather than Source Semantics.
_Avoid_: Native formatting, visual style

**Publication Registry**:
The local installation's authoritative collection of Publications. It determines which documents `pumd` can list or update and is not synchronized through Google Drive or version control.
_Avoid_: Remote catalog, shared registry

**Published Baseline**:
The Desired Document from the last successful publish of a Publication. It is the reference for distinguishing subsequent Markdown changes from reviewer changes in Google Docs.
_Avoid_: Merge base, cached document, remote snapshot

**Merge Conflict**:
An overlap within one reconciliation unit between Markdown changes and Google Docs changes relative to the Published Baseline. `pull` represents a Merge Conflict in Markdown with diff3 local, baseline, and remote sections rather than choosing one side.
_Avoid_: Publication Conflict, sync error, merge failure

**Pending Merge**:
The locally recorded state created when `pull` writes diff3 Merge Conflict markers. It retains the exact pre-pull source and enough remote state for `resolve` to complete the merge or for `pull --abort` to restore it safely.
_Avoid_: Publication Conflict, unresolved pull, dirty source

**Review Barrier**:
Unresolved review feedback that prevents a content-changing publish because `pumd` cannot prove the update will preserve its anchor. Version one treats every unresolved comment as a Review Barrier.
_Avoid_: Comment conflict, warning

**Managed Tab**:
The single Google Docs tab whose content belongs to a Publication. Other tabs in the same document are outside `pumd`'s authority.
_Avoid_: First tab, primary tab, document body
