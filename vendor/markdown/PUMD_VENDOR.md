# `pumd`-owned fork of `mizchi/markdown`

This directory is a source-level fork based on the root package from
`mizchi/markdown` version 0.7.4. `pumd` owns and maintains this fork; local
MoonBit source changes are intentional and do not need to remain patch-free
relative to upstream. The code is distributed under the MIT license in
`LICENSE` and compiled as the local MoonBit package
`rainbowdashy/pumd/vendor/markdown`.

- Upstream repository: <https://github.com/mizchi/markdown.mbt>
- Registry module: `mizchi/markdown@0.7.4`
- Base registry checksum: `28b3eb8e5cf8cfd17f959a6837d0527a8f655a74887174ab8c6c2da44018c62e`

Only the root parser package is vendored. `UPSTREAM_README.md` is retained
verbatim for attribution and upstream documentation, but some packages it
describes (including `x/mdx` and `x/folddown`) are not included here.

The version and checksum identify the fork's upstream base, not its current
source identity. Git history is authoritative for local changes.

## Local divergence

The upstream module declares `supported_targets = "js+wasm"`, although its root
parser package builds and passes its tests on the native backend. Vendoring the
package inside `pumd` removes that module-level restriction.

The fork also owns parser behavior required by `pumd`, including blockquote
lazy continuation, document-absolute provenance for recursively parsed quoted
content, and blockquotes nested in list items. Fork-specific behavior must have
tests in this package and integration coverage through `pumd`'s public seams.

## Updating

Upstream updates are optional manual merges, never wholesale replacements:

1. Fetch the candidate version with `moon add mizchi/markdown@<version>` and
   verify its registry checksum.
2. Compare it with this fork and merge selected upstream changes while
   preserving or deliberately revising every local divergence and test.
3. Retain `LICENSE` and the upstream README as `UPSTREAM_README.md`; omit the
   upstream module manifest and generated interface.
4. Update the base version, checksum, and divergence summary in this file.
5. Run the complete `pumd` test suite with the native backend before committing.

Do not overwrite this directory from the registry: doing so would silently
discard `pumd`-owned parser behavior.
