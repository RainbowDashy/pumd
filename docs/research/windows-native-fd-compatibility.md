# Windows native `Fd` compatibility: `mizchi/x` and `moonbitlang/async`

Research date: 2026-08-02

## Conclusion

There is no released `mizchi/x` version that supports Windows native builds with `moonbitlang/async@0.20.3` or newer. The only published pair satisfying the version requirement is `mizchi/x@0.5.2` plus `moonbitlang/async@0.20.3`, and that pair is source-incompatible on Windows because `mizchi/x` narrows async's opaque Windows `Fd` to `Int`. The official registries currently list `0.5.2` and `0.20.3` as the latest releases, respectively; there is no newer published candidate to pin ([`mizchi/x` manifest](https://mooncakes.io/api/v0/manifest/mizchi/x), [`moonbitlang/async` manifest](https://mooncakes.io/api/v0/manifest/moonbitlang/async)).

This cannot be solved by changing version pins while retaining `async >= 0.20.3`. It requires a new `mizchi/x` release containing the type-preserving patch described below (or an explicitly maintained fork/vendor patch until that release exists).

## Evidence

### The released version boundary

The Mooncakes registry lists 18 non-yanked `mizchi/x` versions and identifies `0.5.2` as latest. Its metadata declares an exact dependency on `moonbitlang/async@0.20.3`; `0.5.1` declared `0.20.0`, and no `mizchi/x` release newer than `0.5.2` exists ([official registry manifest](https://mooncakes.io/api/v0/manifest/mizchi/x), [`v0.5.1` manifest in source](https://github.com/mizchi/x/blob/v0.5.1/moon.mod)). The async registry likewise identifies `0.20.3` as latest, so "`0.20.3` or newer" currently means `0.20.3` ([official async registry manifest](https://mooncakes.io/api/v0/manifest/moonbitlang/async), [async `v0.20.3` release](https://github.com/moonbitlang/async/releases/tag/v0.20.3)).

`mizchi/x@0.5.2` corresponds to upstream commit `e9e62c3`, which bumped async from `0.20.0` to `0.20.3` while adding WASM fd-conversion helpers ([commit](https://github.com/mizchi/x/commit/e9e62c3e3a020115bedca489380ecd0cf48dce7b), [published dependency manifest](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/moon.mod)). There is no fix after that publication: current `main` still declares the native filesystem helper as `fn file_fd_to_int(fd : Int) -> Int` ([current source](https://github.com/mizchi/x/blob/main/src/fs/fs_fd_native.mbt), [main history](https://github.com/mizchi/x/commits/main)).

### Why the pair fails on Windows

In async `v0.20.3`, `Fd` is `#external` on Windows, `UInt64` for the WASM host, and `Int` only on other configurations. The source explicitly describes the Windows representation as an opaque `HANDLE` ([`types.mbt`](https://github.com/moonbitlang/async/blob/v0.20.3/src/types/types.mbt)). This is deliberate ABI modeling: async changed Windows handles from `UInt64` to a pointer-shaped external type because Win32 defines `HANDLE` as `void*` and a fixed `UInt64` is wrong for 32-bit toolchains ([upstream PR #292](https://github.com/moonbitlang/async/pull/292), [merged commit](https://github.com/moonbitlang/async/commit/1c05bf40aab628d3033887cb76d497a2e8f1180f)). Async's filesystem and socket `fd()` methods preserve that `Fd` type rather than returning `Int` ([filesystem source](https://github.com/moonbitlang/async/blob/v0.20.3/src/fs/file.mbt#L21-L24), [TCP source](https://github.com/moonbitlang/async/blob/v0.20.3/src/socket/tcp.mbt#L27-L32), [UDP source](https://github.com/moonbitlang/async/blob/v0.20.3/src/socket/udp.mbt#L75-L80)).

By contrast, `mizchi/x@0.5.2` selects an `Int -> Int` helper for the entire native target in both `fs` and `socket` ([filesystem helper](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/fs/fs_fd_native.mbt), [filesystem target map](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/fs/moon.pkg), [socket helper](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/socket/socket_fd_native.mbt), [socket target map](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/socket/moon.pkg)). It routes one filesystem and four socket handles through those helpers while keeping the public methods typed as `Int` ([filesystem call site](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/fs/fs_native.mbt#L321-L325), [socket call sites](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/socket/socket_native.mbt#L56-L60)). Those declarations produce the five `Fd`-versus-`Int` errors in `pumd`.

The mismatch predates `0.5.2`; that release merely made it explicit through helpers added for WASM. The `mizchi/x` maintainer had already documented that `0.3.3` did not compile on Windows because of an `Fd<>Int mismatch in fs_native.mbt`, and excluded Windows from CI pending a Windows-clean release ([upstream commit](https://github.com/mizchi/x/commit/17c5b9ce9551cb6ac7a68d67f5a9138e03a3205e)). Therefore downgrading `mizchi/x` and overriding its async dependency to `0.20.3` is not a compatibility path.

## Release compatibility result

| Candidate | Declared async version | Windows native with opaque `Fd` |
| --- | --- | --- |
| `mizchi/x@0.5.2` | `0.20.3` | Incompatible: native `fd()` wrappers return `Int` |
| `mizchi/x@0.5.1` | `0.20.0` | Incompatible, including if async is overridden to `0.20.3`: wrappers directly return async `Fd` from functions declared `-> Int` ([source](https://github.com/mizchi/x/blob/v0.5.1/src/fs/fs_native.mbt#L316-L325)) |
| Older `mizchi/x` releases | `< 0.20.0` | Do not provide a declared `async >= 0.20.3` pair; the known `0.3.3` Windows failure confirms the same representation mismatch ([release list](https://mooncakes.io/api/v0/manifest/mizchi/x), [maintainer note](https://github.com/mizchi/x/commit/17c5b9ce9551cb6ac7a68d67f5a9138e03a3205e)) |

Exact compatible pins satisfying the requested constraint: **none**.

## Minimal upstream patch

The correct fix is to preserve async's platform-specific handle type. Converting the Windows handle to `Int` would defeat the opaque pointer representation and reintroduce the pointer-width problem that async's Windows change was designed to avoid ([upstream rationale](https://github.com/moonbitlang/async/pull/292)), so the wrapper return types should be `@async_types.Fd` and should return the upstream handle unchanged.

For the five methods that currently block `pumd`, the smallest functional patch is:

1. Import `moonbitlang/async/types` as `@async_types` in `src/fs/moon.pkg` and `src/socket/moon.pkg`.
2. Change `File::fd`, `Tcp::fd`, `TcpServer::fd`, `UdpClient::fd`, and `UdpServer::fd` from `-> Int` to `-> @async_types.Fd`.
3. Return `self.inner.fd()` directly.
4. Remove the `fs_fd_{native,wasm}.mbt` and `socket_fd_{native,wasm}.mbt` conversion helpers and their target-map entries; async already defines `Fd` appropriately for native Windows, native Unix, and WASM ([async type definition](https://github.com/moonbitlang/async/blob/v0.20.3/src/types/types.mbt)).
5. Regenerate the affected `pkg.generated.mbti` interfaces and add a Windows native CI job.

A complete upstream correction should apply the same change to `PipeRead::fd`, `PipeWrite::fd`, `Input::fd`, and `Output::fd`. Released `0.5.2` gives those shared native/WASM wrappers the same lossy `Int` conversion design ([pipe source](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/pipe/pipe_native.mbt), [pipe native helper](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/pipe/pipe_fd_native.mbt), [stdio source](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/stdio/stdio_native.mbt), [stdio native helper](https://github.com/mizchi/x/blob/e9e62c3e3a020115bedca489380ecd0cf48dce7b/src/stdio/stdio_fd_native.mbt)); async's corresponding methods already return its `Fd` type ([pipe source](https://github.com/moonbitlang/async/blob/v0.20.3/src/pipe/pipe.mbt#L20-L34), [stdio source](https://github.com/moonbitlang/async/blob/v0.20.3/src/stdio/stdio.mbt#L18-L41)).

## Recommended resolution for `pumd`

Do not commit edits under `.mooncakes`, and do not spend more time searching for a version-only solution. The upstream-ready [`mizchi-x-windows-fd.patch`](../../patches/mizchi-x-windows-fd.patch) contains the type-preserving change described above. It is a zero-context patch so that it can be stored without embedded trailing whitespace; apply it to a `mizchi/x` checkout with `git apply --unidiff-zero <path-to-patch>`.

The prepared patch was checked against both current `mizchi/x` `main` and the registry contents for `0.5.2`. In an upstream checkout, native Windows and WASM checks pass for the affected `fs`, `socket`, `pipe`, and `stdio` packages with warnings denied; the focused native socket, pipe, and stdio tests pass (16/16).

`pumd` now vendors that exact `0.5.2` source plus the compatibility patches under [`vendor/mizchi-x`](../../vendor/mizchi-x/PUMD-VENDOR.md). Project-owned code uses `moonbitlang/x` and `moonbitlang/async`; the vendor remains solely for transitive `mizchi/x` imports from the pinned Google dependencies. The root [`moon.work`](../../moon.work) makes the vendor a local workspace member, so those imports resolve reproducibly to it rather than `.mooncakes` ([official workspace documentation](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)). With the vendor active, a clean `moon check --target native` and native CLI build pass, and the full native suite passes (343/343).

A future `mizchi/x` release containing the patch can replace the vendor and restore a registry version pin.
