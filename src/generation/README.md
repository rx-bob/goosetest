# Static suite generation (E3.S1)

`generation::generate(output, manifest, audit)` consumes a completed nonempty
manifest and successful mirror audit. It stages deterministic module paths and
source bytes in caller-owned arrays. It does not write files, run a compiler,
rewrite roots, copy package declarations, or inspect production entry points.
Only `generation::status(output) == 0` permits a caller to materialize the result.
Errors retain a useful source/output path and the first cause; partial output is
never executable input. Artifact ownership and transactional replacement follow
in E3.S4, while execution CLI wiring follows in E3.S3.

## Authored root and generated modules

A consumer checks in a stable root such as:

```goose
// Authored package declarations remain relative to this file.
import goosetest from "../goosetest";

import goosetest_generated.runner;

fn main() {
    exit(goosetest_generated::run_all());
}
```

The pinned compiler requires `main()` with `exit(status)`; it rejects the older
plan example's `main() -> i32`. Declare any additional local/pinned packages in
this same root. Its optional `goosetest_root.build` remains beside it with normal
relative C/include paths. Generated code imports package/module names directly.
No production root is parsed or reconstructed.

Each discovered case gets `case_<index>.goose`, with a direct call enclosed by
`goosetest::execute_case`. There are no function registries or escaping closures.
The runtime recovery boundary remains in the static call ancestry, so a hard
assertion stops its case and returns to dispatch. Original path, namespace,
function, display bytes and declaration line populate `CaseIdentity`; the runtime
copies them before execution. The generated report adapter delegates to the
[shared console renderer](../reporting/README.md), passing the complete selected
case count. It prints original declaration locations, stable IDs, display names,
escaped phase diagnostics and reconciled totals, including cases not run.

Dispatch modules have at most 32 children. Additional levels are emitted until a
single entry remains. Imports are sorted lexically, while calls follow manifest
path/declaration order. Each module directly imports everything it calls. One-case
modules are deliberately simple: even the largest escaped label stays within the
500-line file and 70-line function rules. The runner allocates result storage and
sets case/metadata capacities from the validated manifest, while keeping finite
runtime failure/diagnostic defaults. An incomplete runtime stops further case
bodies and returns status 2.

Fixture-free tests, display labels and per-case fixtures are supported. Fixture
parameters select fresh construction and optional before_each/after_each hooks
with separate recovery boundaries. See [lifecycle contracts](../runtime/LIFECYCLE.md).
Suite hooks now wrap executable suites; setup failure produces explicit case
skips and cleanup still runs. Disabled cases remain deferred to E4.S3. A declared but unused Fixture never runs for fixture-free tests.

## Bounds and source encoding

| Bound | Value |
| --- | ---: |
| Namespace, function and import segment | 48 bytes |
| Original test module path including extension | 100 bytes |
| Display label | 1024 decoded bytes |
| Encoded literal chunk | at most 64 source bytes |
| Dispatch fanout | 32 |
| Default output files | 70000 |
| Default total emitted source | 67108864 bytes |
| Default retained output paths | 4194304 bytes |
| Per-module scratch ceiling | 65536 bytes |

The three output budgets are injectable and nonnegative; exact limits succeed.
Discovery's own suite/case/input limits apply independently. Identifier/path/label
bounds make emitted style guarantees explicit; valid but longer source names
receive an actionable generation error rather than truncated identifiers. The
`goosetest_generated*` namespace prefix is reserved against test namespaces.
Identifiers and import segments are validated separately from literal data.

The dedicated literal encoder escapes quotes, backslashes, controls and non-ASCII
bytes. Short append statements reconstruct exact original bytes inside metadata
helpers, including NUL and UTF-8. This keeps long encoded labels out of both
120-column lines and long wrapper functions. Generation never runs a formatter.

## Basic example and transitional driver

`examples/basic/goosetest_root.goose` now uses generated orchestration. Its small
checked-in `goosetest_generated/` snapshot keeps a clean checkout buildable:

```sh
goose build --debug examples/basic/goosetest_root.goose -o /tmp/goosetest-basic
/tmp/goosetest-basic
```

The independent original runtime harness remains available through
`examples/basic/bootstrap_root.goose`; its package regression keeps that oracle
separate from generation tests.

Until CLI execution and artifact management land, `integration/generation_test.goose`
is a transitional driver for parent-owned fresh destinations. It performs the real
filesystem/mirror/syntax pipeline, stages all modules successfully, and only then
writes them. The destination must not already exist. It does not replace or clean
arbitrary project directories. To inspect a fresh generation snapshot:

```sh
export GOOSE_HOME=/tmp/goosetest-generation-cache
goose build --debug integration/generation_test.goose -o /tmp/goosetest-generate
work=$(mktemp -d)
/tmp/goosetest-generate examples/basic "$work/goosetest_generated"
goosefmt check --config .goosefmt.toml "$work/goosetest_generated"
diff -ru examples/basic/goosetest_generated "$work/goosetest_generated"
```

Adding/changing test files requires regeneration, not edits to the root or a
registration list. After reviewing changes, replace the entire known example
snapshot with the fresh one; do not merge stale generated files. General project
replacement/locking is intentionally deferred to E3.S4.

## Verification

```sh
goose build --debug test/generation_bootstrap.goose -o /tmp/goosetest-generation-unit
/tmp/goosetest-generation-unit
python3 integration/fixtures/generation/verify.py /tmp/goosetest-generate
goosefmt check --config .goosefmt.toml src/generation test/generation \
    test/generation_bootstrap.goose test_support/generation.goose \
    integration/generation_test.goose examples/basic
```

Expected: `generation unit tests passed` and `generation compile tests passed`,
exit 0. Python is the independent temporary parent/process launcher; it builds
through unchanged authored roots in paths containing spaces and another cwd.
It checks local native-package and root-sidecar paths, escaped and maximum-size
labels, exact output determinism, unsupported inputs and exact/over budgets,
original-source failure attribution, and 350 exact ordered case visits across two
dispatch levels. Emitted source passes goosefmt and explicit file/function/column
checks before compilation, without a formatting pass. Disposable consumers and
compiler caches are cleaned even if an assertion fails.

E3.S3 adds generated `completion.goose`: when invoked with the reserved
`--goosetest-completion` argument, it writes `goosetest_generated/completion`
only after execution and reporting finish. The CLI validates this record against
the child status to reject premature exits. Ordinary direct example invocation
without that argument remains unchanged. See [CLI execution](../CLI.md).
