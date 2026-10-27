# Bounded retained runtime (E1.S3)

The package exposes `goosetest::Test`, a borrowed `Results` context, structured
outcomes, and expected-first assertion calls:

| Call | Result on failure |
| --- | --- |
| `t.fail(message)` | Record explicit failure and stop case |
| `t.assert_true(condition, message = "")` | Require true and stop case |
| `t.assert_false(condition, message = "")` | Require false and stop case |
| `t.assert_eq(expected, actual, message = "")` | Record both values and stop case |
| `t.assert_ne(unexpected, actual, message = "")` | Record equal values and stop case |
| `t.check_eq(expected, actual, message = "")` | Record both values and continue |
| `t.assert_contains(expected_fragment, actual_text, message = "")` | Require a byte substring and stop case |
| `t.assert_near(expected, actual, absolute_tolerance, message = "")` | Require absolute proximity and stop case |

See [assertion contracts](../../../src/runtime/ASSERTIONS.md) for float special
values, diagnostic rendering bounds, and custom format-hook limits.

## Ownership and execution

The driver owns four growable arrays: case records, failure records, diagnostic
bytes, and metadata bytes. `new_results` borrows these initially empty arrays.
`Test` borrows that result context. No struct owns multiple resizable tails.
All owners must outlive execution and reporting; the compiler checks references.

A root alongside a `goosetest/` checkout can use:

```goose
// Minimal consumer owns all retained storage through process exit.
import goosetest from "./goosetest";

fn main() {
    var cases: goosetest::CaseResult[>..] = [];
    var failures: goosetest::Failure[>..] = [];
    var diagnostics: u8[>..] = [];
    var metadata: u8[>..] = [];
    var results = goosetest::new_results(cases, failures, diagnostics, metadata);
    var t = goosetest::Test { results: results, .. };
    goosetest::execute_case(t, goosetest::CaseIdentity {
        test_path: "test/example_test.goose",
        namespace_name: "example_test",
        function_name: "test_sum",
        declaration_line: 1,
        ..
    }) {
        t.assert_eq(42, 40 + 2);
    }
    exit(goosetest::run_status(results));
}
```

`execute_case` resets per-case counters, reserves an identity/result record,
invokes the internal `run_case` recovery boundary, and finalizes the outcome.
Hard assertions return from `run_case`, so finalization still executes in the
outer coordinator. Call `execute_case`, not the low-level `run_case`, from a
harness. This replaces S2's `Test {}` construction and direct boundary calls.
The assertion call-site spelling stays unchanged.

Each assertion (including `fail`) increments `assertions` once. `failures` counts
successfully retained failure records. A successful check never erases an earlier
failure. `case_status(t)` reports the current case; `run_status(results)` is the
aggregate process status and must be used when multiple cases share storage:

- 0: one or more finalized cases, all passed or skipped.
- 1: at least one failed case, with no runner error.
- 2: incomplete execution, exhausted/invalid limits, active unfinished execution,
  or no executed/skipped cases (including an entirely filtered inventory).

Every completed case contributes once to totals, regardless of its number of
failed assertions. An empty case passes. Storage exhaustion during a case makes
that case `RunnerError`, rather than also counting it as failed. Exhaustion before
reservation creates no phantom result. The fixed terminal error explains the
missing result and status 2. No later case body executes after a storage error.

## Retained records

`CaseIdentity` is temporary input: test path, namespace, function, display name,
and declaration line. These strings are copied into the metadata arena before
execution. `CaseId` retains offsets and lengths, never those input references.
`CaseResult` holds identity, outcome, assertion count, contiguous failure range,
diagnostic span, and optional skip-reason span. `Failure` holds a phase and message
span. Use `metadata_text(results, span)` or `diagnostic_text(results, span)` to read
retained bytes after fixtures and temporary assertion arguments have left scope.
`case_diagnostics(t)` reads the current completed case's text.

`Phase` represents body, per-case setup/cleanup, and suite setup/cleanup. Phase is
recorded with each failure; lifecycle orchestration remains for E4. `skip_case`
records a skipped result and owned reason without executing a body.
`record_filtered` increments a separate inventory count and allocates no result.
These record operations do not implement annotation parsing or filtering policy.

`Totals` contains passed, failed, skipped, runner errors, filtered, and assertions.
The first four sum to finalized case records; filtered cases are separate.
The runtime never prints. The integration harness renders the static terminal
message only when demonstrating a runner error.

## Budgets and failure atomicity

`Limits` defaults are finite and independently injectable:

| Field | Default | Scope |
| --- | ---: | --- |
| `cases` | 4096 | Retained case records, including skips/errors |
| `failures` | 16384 | Retained failure records across all cases |
| `diagnostic_bytes` | 1048576 | Retained formatted diagnostic bytes |
| `metadata_bytes` | 1048576 | Owned identity fields and skip reasons |

Zero is valid. Negative limits produce `InvalidLimits` and status 2 without
executing a case. Remaining-capacity subtraction avoids overflowing a size sum.
A case reservation checks all identity fields and skip reason before appending
anything. A failure checks record capacity and known message/envelope size before
formatting, then validates the complete formatted byte count before committing
both bytes and record. No partial message, silent truncation, or dropped record
can yield a successful result. Exact limits work; exceeding by one byte does not.

The first terminal error remains available through `terminal_diagnostic(results)`
as a static literal, independently of all arena budgets. Already committed cases,
failures, and bytes remain readable. `results.incomplete` and status 2 distinguish
exhaustion from an ordinary failed assertion.

Byte limits bound retained arenas and direct string/collection rendering. Scalar
formatting uses finite scratch; custom hooks and opaque/default struct formatting
use temporary scratch whose work and allocations remain outside `Limits`. Only
bounded bytes are appended after they return. Passing assertions never invoke
formatting. Runtime aborts remain fatal process failures, distinct from recoverable
framework assertions.

## Compiler constraints

See [compatibility.md](../../../docs/compatibility.md) for the pinned baseline.
Namespaced implementations use narrow global bridges for the installed UFCS
lookup. A same-named user function may shadow a bridge; use a qualified call such
as `goosetest::assert_eq(t, ...)` in that scope.

Unused non-generic hard assertions are eagerly checked without a recovery
ancestor on this compiler. `fail`, `assert_true`, and `assert_false` therefore
use a generic context parameter; typed helpers still require `Test&`, and condition
and message arguments remain `bool` and `u8[:]`. Equality functions already defer
through their value type. Import-only consumers compile; real assertion calls
outside the required ancestor still fail compilation. Soft checks also need the
boundary now, because a budget error stops execution even when assertions are soft.

## Reproducible verification

Run from the repository root. Builtin assertions independently inspect counters,
outcomes, spans, temporary-value ownership, format-hook calls, and exact budgets.
The parent checks actual 0/1/2 process statuses. Source files with `.data` suffixes
are materialized only inside a disposable directory.

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
    status=0
    "$work/harness" --limit >"$work/limit.log" 2>&1 || status=$?
    test "$status" -eq 2
    grep -F 'incomplete run: case record limit exhausted' "$work/limit.log"

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
    goosefmt check --config .goosefmt.toml goosetest.goose src test test_support integration
)
```

Historical POCs and `.goose.data` inputs remain outside formatter discovery.
The earlier compatibility fixture matrix remains independently runnable.
