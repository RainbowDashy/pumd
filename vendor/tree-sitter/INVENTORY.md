# Tree-sitter asset inventory

`pumd` vendors the C runtime, generated parsers, external scanners, and reviewed
highlight/injection queries below. Normal builds compile only these files: they
never download an asset, locate a grammar, or read a `.scm` file. The query
strings in `generated/highlight_queries.h` are generated from the checked-in
query files with `npm run generate:highlight-queries`; consumers derive each
byte length with `sizeof` rather than generated length objects. The generated
header has SHA-256
`2235ee049fed0b4b26239651c32213ecc3b42f8508a33d9bb22f7d0eb1d92ade`.

## Runtime

| Asset | Upstream | Pin | SPDX | Local assets | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Tree-sitter C runtime | https://github.com/tree-sitter/tree-sitter | `v0.26.11` / `64402de2857cc197ecc4ca3bc144ea91fda7e72e` | MIT | `runtime/include`, `runtime/src`, `runtime/LICENSE`, `runtime/LIBRARY-LICENSE` | `api.h` `379611afd1492ece6a1c4c503ffc9c2a9827152444583205c6f35040dd418bfe`; `lib.c` `4e28f87edb86e5134d36ff7ba7e09a964ba9966a4b620c2735e3572b53c157d3` |

The bundled runtime supports generated language ABI versions 13 through 15.

## Executable vendor contract

`pumd_syntax_highlight_vendor_contract` iterates the 16 canonical parser
assets in the C adapter. It checks each compiled parser export, its generated
Tree-sitter ABI, the primary highlight query plus any configured supplement,
and the immutable revision/SPDX metadata mirrored from this inventory. The
contract never reads vendored files or checksums generated sources at runtime;
the SHA-256 values below remain the reviewable provenance record.

## Parsers and queries

The parser SHA covers `grammars/<name>/src/parser.c`; the scanner SHA is shown
where the grammar has one. `H` is the `queries/<name>/highlights.scm` SHA.
All entries are MIT licensed. The generated source's Tree-sitter ABI is shown
in parentheses.

| Canonical language | Aliases | Upstream pin | Local parser assets and SHA-256 | H SHA-256 |
| --- | --- | --- | --- | --- |
| javascript | `js` | https://github.com/tree-sitter/tree-sitter-javascript `58404d8cf191d69f2674a8fd507bd5776f46cb11` (15) | parser `67209ca7ef6e1a4f74e29e48b5928455f892fe1821a3960fbcd62f4e972f7384`; scanner `b3d3f64284d97bf80749c026862427782cf7ecc0b7dc094e6698ab311c9a42c7` | `d3630ae6dc9b2b27b230b5f8bb92b05cd491fb12bff353dae62a0a6d780461ee` |
| jsx | — | javascript pin above (15) | javascript parser plus `queries/javascript/highlights-jsx.scm` | javascript H plus JSX query |
| typescript | `ts` | https://github.com/tree-sitter/tree-sitter-typescript `75b3874edb2dc714fb1fd77a32013d0f8699989f` (14) | parser `74fe453edd70f4eae9af0a1050cbd7943d8971d59165b6aaebbaa0a0b716d1aa`; scanner `1efe473203e9087ae56c5573c39fd1475344ede33266f7c74db0b0b63e632029` | `e0c35adb819127bfd4f853fac5419e7d8ba44760246201d04a4a5ce0228a10c5` |
| tsx | — | typescript pin above (14) | parser `1902cb53fa7ff5179df89b2eea863165e84c8cc866226419dc26921d8c055885`; scanner `2c3b1c961b13857e56534e8f2bf4fbd4d42077acd68a4d15d750b3cf8eec812a` | `8471f57cb34ccbb801df07e99393ae20716d7a40b3cd5c32325298bbbe6807ee` |
| shell | `sh`, `bash`, `zsh`, `console` | https://github.com/tree-sitter/tree-sitter-bash `a06c2e4415e9bc0346c6b86d401879ffb44058f7` (15) | parser `5ad30bb1a260c76df5397490b8bd97e272e62ed9c99be36fa53da959d7667e7f`; scanner `7cc25d70626f8939b35ecd504bf724e2001b817412aa29bceb4c4955a91558a9` | `b74220d954f485b7626d2b2b61f37b522e12eb1830803e388e57dd797dc99f11` |
| powershell | `ps1` | https://github.com/airbus-cert/tree-sitter-powershell `e7bd348c49fdfd5c853a146a670965ba516a6239` (15) | parser `f39f67abaae4c488ccea5d9bbd003ef0b00c303779e0491950886a12a9305720`; scanner `cf366b70e258a0ac1eb264ac0f4165c8f0c1b943d1a6e9db9d291c6cf178221f` | `ca7fbd3725832082793510fd478eefeb8ee1588adbbf8d1ff2dcb066249b35ac` |
| json | — | https://github.com/tree-sitter/tree-sitter-json `001c28d7a29832b06b0e831ec77845553c89b56d` (14) | parser `e8e1ff5df0d73e3b82574129724e68ef4fa0faf1b8c43dd3f5c1a84839f830ab` | `0511524465b56aed122580792254e68b6abbbfde7119f1d02b135acbe278233f` |
| yaml | `yml` | https://github.com/tree-sitter-grammars/tree-sitter-yaml `a1c4812a73ec5e089de8e441fdea3a921e8d5079` (15) | parser `02c5d32e95fa018a3c3ba7d7134d84bb7d5595c8874aa7ae6582745d9b40dede`; scanner `a510c0ca699cf3853bd2192bf103e11132414bc002fe952a88a7106ffb5d44e9` | `2fbfbbd5ca0928d0a7e09e59f8f2964b14a328a7ee0ce799270d9013dcce49a0` |
| toml | — | https://github.com/tree-sitter/tree-sitter-toml `64b56832c2cffe41758f28e05c756a3a98d16f41` (14) | parser `1991a2608e6f0214e563fe5f762e8df72954dc69a3dd9a1e22ea8a870e4052c3`; scanner `b25ff3b5034f40046e9a041d1e9110aa46d081706bbd1b748b480701aa6f5bde` | `2fb5c61d33a70389312254c9c392e2c5dd6313d958d6e5f8f74cadd5e0811707` |
| html | — | https://github.com/tree-sitter/tree-sitter-html `73a3947324f6efddf9e17c0ea58d454843590cc0` (14) | parser `65768172733b3bbe461cbdc14ea928f00fbfcc51d8ac68f0a5c72071c6a0bbf1`; scanner `5c0a0567e010277b81fe63be0acd04f6b44c3ef3063ac01429b910c1d22f0dca` | `1ebb3811a8cdc054385b847a3aac6fbf7079faefd5b3dfab5bbad256cd5afdcf` |
| css | — | https://github.com/tree-sitter/tree-sitter-css `dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f` (15) | parser `2e5150071220012ee635ac9e2119f4f3a93e0b51a7a3b69ab0cd87c18cf5e51e`; scanner `18dae8c8c4f515f28a3dc7ffb5bda259b06013a752921dc411a2fad8ecf78988` | `23f7948a3817a0d06d7120158c3bee4ec5b58daa77e524985a4738b364db17b2` |
| xml | — | https://github.com/tree-sitter-grammars/tree-sitter-xml `5000ae8f22d11fbe93939b05c1e37cf21117162d` (14) | parser `e00f74ae7edcfc5e0cf9dc551a41a02e88a86dad9d6d13820e292bde794cdd94`; scanner `4b0f66625c8bd23ec5cde906206083a3cc39e9fedf6a71fb0747bfca6ca19c26` | `aa4a561c846928c3a4d885acbe690a60689661a45684babe16cf8b7a1509b610` |
| sql | — | https://github.com/DerekStride/tree-sitter-sql `v0.3.9` / `64d6707541898bf17a306033050b1932524e215f` (15) | parser `e10b56aa2caaa369d085f7a5e43ec14adfad309c2a7a3a64e70bceef533dfeb7`; scanner `de17b5cffc3c86f56cf6630abb969330c3c839a81ece0b901bdac0ecee93c403` | `80e726903b67fbe471bf1272a447ab6a6758e95654f9e9c8f5c2e4af729af8de` |
| markdown | `md` | https://github.com/tree-sitter-grammars/tree-sitter-markdown `a0a00f817d02412bd92c54d316f164d827b57b5c` (15) | parser `0f51c93b5d79d08bc74088d91a9aafb7e40ad7e2f169164865c01d392277bb07`; scanner `02834bcbaf0cf51178e74450d487cc0231b9a52541cd374527ee35cfaf17fd4a` | `2eb06e766ccd672d49599d14f398f07f4f5f7f2208262993d3cd9207c1078e2f` |
| http | — | https://github.com/rest-nvim/tree-sitter-http `db8b4398de90b6d0b6c780aba96aaa2cd8e9202c` (14) | parser `7f42901a31e547bbf473a174a154e4bc452441c979bae1fc689afa2f58bda62e` | `9763d89ca17a4101ac94d9cc8002ff423c2e2c0548644af883247b64bce162ad` |
| protobuf | `proto` | https://github.com/mitchellh/tree-sitter-proto `42d82fa18f8afe59b5fc0b16c207ee4f84cb185f` (13) | parser `0029c486379508543e4822d6c7842df15058fe560377a19a51992eeb527013b6` | `6d5c47bdfeccf1f3c2c815151987674703c5b69a2fe6575650ac8c8939ea3b55` |

The SQL parser is pinned to upstream `v0.3.9` (64d6707) rather than a later
release because the generated tables grew from 17,329 states / ~2.4 MiB at
v0.3.9 to 30,622 states / ~10.5 MiB on current `main` (v0.3.11-era) without
new dialect coverage relevant to `pumd`. The v0.3.9 release includes the
TSQL additions (`@param` identifiers, `N'...'` strings, `OBJECT_ID`) plus the
existing PostgreSQL, MySQL, and Oracle best-effort keyword coverage; dialect-
specific syntax outside the grammar still degrades safely to plain code. The
upstream revision intentionally has no `src/parser.c`; it was generated once
with `tree-sitter-cli@0.26.3`, then checked in; normal builds do not run a
generator. The Protobuf include spelling and the TypeScript/TSX/XML external
scanner include paths are normalized only to make isolated, no-include-path C
translation units work. Their checksums above identify the exact committed
artifacts.

## Injection allowlist

The enabled injection paths are deliberately finite:

- HTML: `script` to `javascript`; `style` to `css`.
- Markdown: an explicitly tagged fenced block to an alias in this table.
- JavaScript: no dynamic injection is enabled by the adapter until its query
  predicate semantics are explicitly evaluated.

The HTTP injection query is retained and included in the generated query asset,
but is not an enabled path in this adapter revision.

No injection target is inferred from a filename, shebang, user environment, or
the filesystem. Unsupported injection predicates, malformed source, unavailable
grammars, or invalid spans are a negative native result and leave the renderer's
existing plain code treatment in place.

## Distribution impact

Measured on 2026-08-06 on macOS arm64 with MoonBit 0.1.20260803 and Apple
Clang 16, using a clean
`moon build --target native --release --strip --frozen cmd/pumd`:

| State | Build time | Stripped CLI size |
| --- | ---: | ---: |
| Baseline `02a0bc5` | 12.13 s | 2,893,736 bytes |
| Bundled Syntax Highlighting | 16.75 s | 20,976,040 bytes |
| SQL `v0.3.9` pin + size flags | 14.68 s | 11,958,536 bytes |

The bundled parsers originally added 18,082,304 bytes (17.24 MiB, a 624.9%
increase). Pinning the SQL grammar to `v0.3.9` removes ~8.1 MiB of generated
parse tables, and the size flags (`-Os -flto -ffunction-sections
-fdata-sections` for native-stub compilation plus `-flto` at link time, wired
through `options(link: ...)` in `moon.pkg`) remove a further ~0.6 MiB. The
optimized bundle adds 9,064,800 bytes (8.64 MiB, a 313.2% increase) to the
baseline. Timing is machine-local evidence rather than a performance budget.
