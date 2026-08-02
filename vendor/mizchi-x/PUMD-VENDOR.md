# Vendored `mizchi/x`

- Upstream: <https://github.com/mizchi/x>
- Published version: `0.5.2`
- Base commit: `e9e62c3e3a020115bedca489380ecd0cf48dce7b`
- Local patches:
  - [`../../patches/mizchi-x-windows-fd.patch`](../../patches/mizchi-x-windows-fd.patch)
  - [`../../patches/mizchi-x-windows-tls-server.patch`](../../patches/mizchi-x-windows-tls-server.patch)

The `Fd` patch preserves `moonbitlang/async/types.Fd` in native and WASM wrappers instead of narrowing Windows's opaque handles to `Int`. The TLS patch keeps the existing PEM-based server API off Windows and exposes the PFX-based server API required by `moonbitlang/async` on Windows. The root [`moon.work`](../../moon.work) resolves `mizchi/x` from this local workspace module; the version in [`moon.mod`](../../moon.mod) records the upstream provenance pin.

Upstream `*_test.mbt`, `*_wbtest.mbt`, and `*.mbt.md` files are omitted so workspace-wide commands run the project's test suite rather than the dependency's platform-sensitive test corpus.

To refresh the vendor, import the listed upstream commit, apply both patches with `git apply --unidiff-zero`, omit those test/doc-test files, and rerun the native and WASM checks documented in [`../../docs/research/windows-native-fd-compatibility.md`](../../docs/research/windows-native-fd-compatibility.md).
