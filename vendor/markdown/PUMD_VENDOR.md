# Vendored `mizchi/markdown`

This directory contains the root package from `mizchi/markdown` version 0.7.4.
It is distributed under the MIT license in `LICENSE` and is compiled as the
local MoonBit package `rainbowdashy/pumd/vendor/markdown`.

- Upstream repository: <https://github.com/mizchi/markdown.mbt>
- Registry module: `mizchi/markdown@0.7.4`
- Registry checksum: `28b3eb8e5cf8cfd17f959a6837d0527a8f655a74887174ab8c6c2da44018c62e`

Only the root parser package is vendored. `UPSTREAM_README.md` is retained
verbatim for attribution and upstream documentation, but some packages it
describes (including `x/mdx` and `x/folddown`) are not included here.

## Local patch

The upstream module declares `supported_targets = "js+wasm"`, although its root
parser package builds and passes its tests on the native backend. Vendoring the
package inside `pumd` removes that module-level restriction. No MoonBit source
is modified.

## Updating

Fetch the intended version with `moon add mizchi/markdown@<version>`, replace
the package-root files from the downloaded module, retain its license and
README (renamed to `UPSTREAM_README.md`), omit its module manifest and generated
interface, verify the registry checksum, and run the complete `pumd` test suite
with the native backend before committing.
