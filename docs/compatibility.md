# Compiler and style contract

The initial supported baseline is **Goose v2026.3 on macOS arm64**. No compiler
upgrade is required. These checks were run on 2026-10-26 using:

- Installation: `/Users/bob/.local/share/goose/v2026.3/goose-v2026.3-macos-arm64/goose`.
- Launcher: `/Users/bob/.local/bin/goose`, a symlink to that installation.
- `goose version`: `goose runtime 4d3da949e563`.
- Compiler SHA-256: `1a95a810fd78c4938648d1c32d4c1a16331e97aa3962515a6aad5e5b478d157c`.
- Formatter: `/Users/bob/.local/bin/goosefmt`.
- Formatter SHA-256: `5b20384de5c3327444f1bfb2bd067aed8a679eb9c67bafb6255ad43123ac694d`.
- Native build selected clang 17.0.0. Other platforms remain unverified.

Use `goose version`, `goose --help`, `goose check FILE`, and
`goose build --debug FILE -o OUTPUT`. This release rejects `goose --version`.
`-o` has no long-form equivalent. Set `GOOSE_HOME` to an owned temporary directory
when isolating compiler caches. Debug native builds are the supported test path.

## Verified language contract

The standalone [compatibility oracle](../test_support/oracles/compatibility_test.goose)
imports a miniature fixture package, **not the shipping assertion runtime**.
Its built-in assertions independently verify these properties:

- Root-only package declarations resolve a local package. Package-root imports
  and sibling-relative imports resolve inside that package, independently of the
  consumer's root. Every module directly imports the declarations it uses.
- The public spelling remains `goosetest::Test` and `t.assert_eq(expected, actual)`.
  Implementations and the generic `goosetest::run_case<F>` boundary are namespaced.
  Only the assertion bridge is global; execution stays explicitly qualified.
- UFCS searches the caller namespace, then globals. It does **not** search the
  receiver type's namespace. The bridge works from two different user namespaces.
  A same-named user function hides the entire global overload set, even if its
  signature is incompatible. Qualify `goosetest::assert_eq(t, ...)` in such a scope.
- `return from goosetest::run_case` crosses generic assertion/bridge calls, stops
  the body and remaining boundary block, and resumes after the intended boundary.
  Nested boundaries catch at the nearest matching invocation. A following case
  still executes. Every assertion call path needs that ancestor, even when its
  comparison would pass; unused runtime branches are not a substitute.
- `u8[:]` parameters accept literals and mutable storage through const-generic
  specialization. Writes through a literal specialization are rejected.
- A `.=` reference into growable storage survives 256 further pushes and still
  mutates the original element. An existing slice retains its original length.
  Shrinking storage with a live reference is rejected. These are borrowed views,
  not permission to retain references after their owner dies.
- Global `fn main()` returns nothing. Use builtin `exit(status)` to propagate a
  nonzero result: the separate status probe returns 7 to its parent. Runtime
  harnesses call `exit(result)` rather than return a status from `main` or
  silently discard it. A namespaced file's `fn ::main()` has global lookup scope;
  calls to namespaced helpers must be qualified.

Use the installed `docs/packages.md`, `docs/reference.md`, and
`docs/goose_spec.md` as language evidence. Current online UFCS or `defer` examples
may describe a newer compiler. This release's installed specification provides
no `defer` contract on which this project relies. Cleanup must be explicit around
recovery boundaries; no cleanup guarantee is inferred for aborts or process exit.

The runtime remains standard-library-only. Native process/filesystem adapters
belong to the CLI platform boundary; importing the assertion package does not
link those adapters. The compiler-contract fixture itself adds no native adapter.

## Style baseline and formatter limitations

The normative guide is `/Users/bob/repos/pretty-goose/docs/styleguide.md`.
The root `.goosefmt.toml` adopts that repository's settings supported by the
installed formatter: 4 spaces, 120 columns, 500 lines per file, at most 6 parameters
and 3 return values, naming and all available formatting rules enabled.

The installed formatter rejects the newer configuration keys listed as comments
in `.goosefmt.toml`, including `max_function_lines = 70` and `function_length`.
Those remain review requirements, not disabled supported rules. Review additionally
enforces the 70-line function limit, headers, namespace-before-import order,
direct/alphabetized imports, reference binding, bounded loops, and simple assertions.
The supplemental source checker enforces the function-line bound. Intentional
historical POCs and inert diagnostic data are excluded, not shipping modules.

To reproduce the configuration mismatch, pass a temporary config containing:

```toml
[lint]
max_function_lines = 70
```

`goosefmt check --config TEMP_CONFIG test_support/oracles/compatibility_test.goose` exits 2
with `invalid or unknown config setting`. The same happens for each commented key.

The valid compiler fixture `global_bridge.goose.data` reproduces a second defect:
materialize it as `.goose`; `goose check` succeeds, but `goosefmt check` reports
G011 on `fn ::main()` and formatting changes it to `fn::main()`. The real fixture
uses a small global entry file and a separate deliberate global bridge module,
keeping implementations namespaced and naming checks enabled. Formatter output
also spells sibling imports `import.marker;` and negation `assert( !value);`.
These whitespace quirks compile successfully; the positive fixture tests the
formatted output, so formatter acceptance never substitutes for compilation.

Run `task check` for shipping root modules, `src/`, `test/`, `integration/`,
`test_support/`, `scripts/`, `examples/`, and representative generated output.
The command builds and executes the repository and basic example before checking
those generated files. Historical `poc/` and `.goose.data` diagnostic/reproducer
inputs are intentionally excluded. Do not recursively format the POCs or
materialize invalid fixtures inside discovered roots.

See the [fixture instructions](../test_support/compatibility/README.md)
for independent positive, negative, and process-status checks. The maintained
[process verification matrix](../integration/fixtures/README.md) covers framework
failure contracts and self-hosting separately from these compiler probes.

## Reproduce the supported developer workflow

Prerequisites on `PATH`: the pinned `goose` compiler, Apple command-line tools
with `clang`, Python 3, `goosefmt`, and Task. Use an unprivileged user because
permission-denial checks must actually fail access. Native adapter support has
been verified only on macOS arm64; do not infer Linux or Windows support from
the runtime's standard-library-only design.

From a clean checkout's root:

```sh
goose version
task build
task example
task test
task check
build/goosetest --help
```

Task compiles native-sidecar automation scripts with `goose build --debug`, then
runs their executables. Do not replace this with an interpreted script invocation:
native external symbols require the compiled path. `build/goosetest` is the CLI;
`task test` invokes the independent verification parent via `scripts/verify.goose`.
The compiler requires `-o` for output selection because it provides no long option;
CLI project, filter, suite, compiler, and deadline options use their long spelling.

An explicit local package source is the verified installation method; see the
[root wiring](../README.md#use-a-local-checkout). The example and copied-consumer
checks exercise source resolution from different working directories. No remote
repository source or package registry is required or claimed to be verified.

The [pretty-goose adoption recipe](adopting_pretty_goose.md) describes the isolated
consumer now included in verification. The real pretty-goose working tree remains
outside this implementation; its production snapshots are fixture data.

## E6.S4 verification record — 2026-10-27

The final source tree was copied without `build/` or the repository's generated
self-test directory, retaining only the maintained basic generated snapshot.
With a fresh, isolated `GOOSE_HOME`, these commands passed sequentially:

- `task build`: produced `build/goosetest` through the native debug build path.
- `task example`: four discovered cases passed, including the fixture integration
  case; eight assertions, status 0, no manual test registration.
- `task test`: 170 self-hosted cases plus all nine independent regression matrices
  passed, including injected assertion status 1, large exact inventories, and
  compiler/runtime cancellation and deadline cleanup.
- `task check`: 312 shipping/generated Goose files passed formatting and the
  supplemental 70-line function bound.

The basic copied-consumer generation regression also passed, including authored
native sidecars and package resolution outside the checkout. Every README Goose
excerpt matched its compiled maintained source; local documentation links resolved.
A disposable 72-line function passed the installed formatter but was rejected by
the supplemental checker with status 2 and a file/line diagnostic. This confirms
that the formatter's missing function-length rule cannot silently pass that case.

These results are scoped to the supported baseline and implemented stories.
E6.S3 adoption evidence was not yet available at the time of this E6.S4 record;
its later verification is recorded below.

## E6.S3 adoption verification — 2026-10-27

The isolated consumer matrix is now part of `task test`. Six production modules
match their recorded SHA-256 snapshots before and after execution. The selected
original test/helper declarations match the archived original source exactly and
pass using builtin assertions before conversion. The converted consumer then
passes two mirrored unit cases and one integration case through the public
package and generated runner, outside this checkout.

A changed formatter expectation exits 1, reports exactly its case as failed,
retains both other passing IDs, and prints the declaration location, custom
message, and distinct expected/actual formatting values. The consumer's authored
and generated sources pass formatting checks; original production snapshots stay
byte-for-byte unchanged.

Final `task test` passed all 171 self-hosted cases and all ten independent
matrices. Final `task check` passed the four-case basic example and checked 314
shipping/generated Goose files, including the supplemental function-line bound.
The original pretty-goose checkout was inspected read-only: all 23 file hashes
and its pre-existing Git status matched before and after this work, including
its unchanged Taskfile. No original test command was run there. See the
[adoption guide](adopting_pretty_goose.md) for provenance and the deliberately
limited package-boundary migration recipe.

## E2.S3 profile recovery verification — 2026-10-28

The recovery and lifecycle consumer passed under both debug (`-O0`) and
optimized (`-O2`) profiles with Goose runtime `4d3da949e563`, Apple clang
17.0.0, on macOS arm64. Each run confirmed soft-check continuation, hard
assertion recovery, one cleanup after partial fixture setup, stable case IDs,
fail-fast reporting, and disabled-only selection without suite hooks or body
execution. Fatal `assert(false)` remained a status-2 execution failure with no
completed test inventory in both profiles. The independent execution matrix also
passed abort and explicit-exit process checks in both profiles. These compiler
and platform results are verified; other platforms are not implied.
