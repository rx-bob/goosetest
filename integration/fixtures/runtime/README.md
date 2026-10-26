# One-case runtime (E1.S2)

The root `goosetest.goose` facade exposes `goosetest::Test`, qualified
`goosetest::run_case`, and these global assertion bridges:

| Call | Result on failure |
| --- | --- |
| `t.fail(message)` | Record explicit failure and stop case |
| `t.assert_true(condition, message = "")` | Require true and stop case |
| `t.assert_false(condition, message = "")` | Require false and stop case |
| `t.assert_eq(expected, actual, message = "")` | Record both values and stop case |
| `t.assert_ne(unexpected, actual, message = "")` | Record equal values and stop case |
| `t.check_eq(expected, actual, message = "")` | Record both values and continue |

For a consumer root alongside a `goosetest/` checkout:

```goose
// Minimal public-package consumer.
import goosetest from "./goosetest";

fn main() {
    var t = goosetest::Test {};
    goosetest::run_case(t) {
        t.assert_eq(42, 40 + 2);
    }
    exit(goosetest::case_status(t));
}
```

Every invocation resets `assertions`, `failures`, and owned `diagnostics` before
running its block. Each assertion, including `fail`, increments `assertions` once.
Every failed assertion increments `failures`; successful checks never erase a
failure. Read `case_status(t)` **after** the boundary returns: 0 means this case
passed, 1 means it failed. Count this result once per case, even if several soft
checks failed. A zero-assertion case passes. Retain aggregate status in the caller
before reusing the context, as `integration/runtime_harness.goose` demonstrates.

Hard assertions use the compiler's non-local return, not builtin `assert` or
process termination. They skip the remaining test/helper/block statements and
resume after `run_case`. Its implementation deliberately has no finalization
after the block, since a hard return would skip that code too. Runtime assertions
do not print. An unrecoverable runtime abort remains a process failure.

Diagnostics are formatted on failure while arguments are alive, using standard
Goose formatting and custom type format hooks. Success performs comparisons and
counter updates only. The context owns the resulting text until the next reset;
do not keep a borrowed view across context reuse. Scalar, string, and slice values
use native equality; take slices when comparing arrays of different sizes.
Expected/actual labels always retain argument order. Diagnostic storage is a
single growable tail; explicit limits, stable result records, and retained
multi-case results are the next story, E1.S3.

## Pinned compiler constraints

See [compatibility.md](../../../docs/compatibility.md) for the version and style baseline.
The implementation stays namespaced; the facade provides only assertion bridges
for this release's UFCS lookup. User functions with the same names can shadow
those bridges; qualified `goosetest::assert_eq(t, ...)` remains available.

An additional compiler probe found that **unused non-generic hard assertion
functions are instantiated without a recovery ancestor**. That makes an ordinary
import fail even when the consumer does not call that assertion. Accordingly,
`fail`, `assert_true`, and `assert_false` defer instantiation through a generic
context parameter, both in the facade and implementation. Their implementation
helpers still require `Test&`; condition and message parameters retain `bool` and
`u8[:]` types. Equality assertions already defer through their value type parameter.
No extra user argument or call-site spelling is needed. Import-only and partial-API
consumers compile, while actual hard calls outside `run_case` remain rejected.

## Reproducible verification

Run from the repository root. Builtin assertions independently check runtime
state, diagnostic bytes, continuation sentinels, and format-hook call counts.
The parent shell checks real process statuses; runtime verdicts alone cannot
make the checks pass. All generated files and caches stay in an owned temp folder.

```sh
(
    set -eu
    work=$(mktemp -d "${TMPDIR:-/tmp}/goosetest-runtime.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    export GOOSE_HOME="$work/cache"

    goose build --debug test/runtime_test.goose -o "$work/unit"
    "$work/unit"
    goose build --debug integration/runtime_harness.goose -o "$work/harness"
    "$work/harness"
    status=0
    "$work/harness" --fail || status=$?
    test "$status" -eq 1

    ln -s "$PWD" "$work/package"
    fixtures=integration/fixtures/runtime
    cp "$fixtures/import_only.goose.data" "$work/import_only.goose"
    goose build --debug "$work/import_only.goose" -o "$work/import_only"
    "$work/import_only"
    cp "$fixtures/outside_boundary.goose.data" "$work/outside_boundary.goose"
    if goose check "$work/outside_boundary.goose" >"$work/rejection.log" 2>&1; then
        echo "unexpected success outside recovery boundary" >&2
        exit 1
    fi
    grep -F 'no enclosing call of goosetest::run_case' "$work/rejection.log"
    goosefmt check --config .goosefmt.toml goosetest.goose src test integration
)
```

Historical POCs and `.goose.data` inputs remain outside formatter discovery.
The earlier compatibility fixture matrix remains independently runnable.
