# Markdown Publishing

The language used to describe how a local Markdown document becomes and remains an editable native document on a publishing platform.

## Language

**Desired Document**:
The complete Google-Docs-native structure that publishing intends to produce from the current Markdown source, independent of any document currently stored remotely. It is expressed as native elements such as paragraphs, text runs, bullets, tables, and inline objects rather than Markdown constructs; source provenance may be attached as metadata but is not part of the native content.
_Avoid_: Document IR, request plan, API document

**Style Profile**:
The coherent set of native formatting defaults that publishing applies to body text and supported document elements. Version one has one built-in profile.
_Avoid_: Stylesheet, theme, template

**Blockquote**:
A quoted block of Markdown content introduced by the `>` marker and published as visibly distinct native document content.
_Avoid_: Backquote, backquote block marker

**Managed Authorization**:
An author's grant of Google access through the OAuth identity owned and operated by `pumd`. It is a future authorization mode intended to remove user-owned Google Cloud setup.
_Avoid_: Default ADC, built-in credentials

**Project Authorization**:
An author's grant of Google access through the OAuth identity owned by a user-selected Google Cloud project. It is the default authorization and provides independent consent configuration and quota ownership.
_Avoid_: BYO client, custom credentials
