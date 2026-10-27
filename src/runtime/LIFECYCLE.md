# Per-case fixtures and recovery

A discovered `test_*(t: goosetest::Test&, f: Fixture&)` gets a fresh local
`Fixture { .. }` after its case record has been reserved. Explicit field defaults
run once per fixture; remaining fields receive their language defaults. Fields
without a legal default, such as an uninitialized nonoptional reference, remain
compiler errors. No fixture state is reused between cases.

A suite may also contain `test_*(t: goosetest::Test&)`. Those functions construct
no fixture and run neither fixture hook, even when the file declares `Fixture`
and both hooks. Constructor side effects therefore occur only for cases whose
signatures request a fixture.

Supported hook signatures are:

```goose
fn before_each(f: Fixture&) { }
fn after_each(f: Fixture&) { }
```

A hook needing assertions takes `t: goosetest::Test&` first, followed by
`f: Fixture&`. Choose one form per hook name; duplicate forms are discovery
errors. Hooks are optional. Suite hooks and disabled cases are described below;
selection and fail-fast follow the policy below.

Setup, body and cleanup each execute inside their own `run_case` recovery
boundary. Hard assertions stop only the current phase. Any setup failure,
including a soft `check_eq`, prevents the body from running. Cleanup is attempted
once with the same fixture after setup or body failure. Its failures append to
earlier failures and retain their cleanup phase. One case with several failed
phases is still one failed case, with each assertion counted once.

Default and partially initialized fixture states **must be safe to clean up**.
For example, initialize resource-ownership flags to false, set them only when
acquisition succeeds, and let cleanup test those flags before releasing anything.
Do not assume setup reached its last statement. Failed cleanup does not erase
an earlier cause.

Resource-limit errors also attempt the cleanup callback, but exhausted recording
capacity cannot preserve additional diagnostics. Assertions may stop that cleanup
phase; the original terminal error remains and status is 2. Subsequent cases do
not construct fixtures once the run is incomplete.

There is no cleanup guarantee after fatal Goose checks, constructor failure,
process exit, native crashes, deadlines or process termination. This mechanism
uses explicit recovery boundaries, not `defer` or process isolation.

The generator uses `execute_fixture` for record ownership/finalization and
`run_phase` for phase labels and recovery. These are qualified runtime helpers;
test authors normally use discovered signatures and hooks. `run_phase` returns
whether that phase recorded no failure and the run remains complete. It never
resets failures from earlier phases. The console renderer consumes the finalized
case only after cleanup returns.

Verification:

```sh
goose build --debug test/runtime_test.goose -o /tmp/goosetest-runtime
/tmp/goosetest-runtime
python3 integration/fixtures/lifecycle/verify.py /tmp/goosetest
```


## Suite setup and cleanup

`before_all()` and `after_all()` run once around a suite with selected executable
cases. Either may independently take `t: goosetest::Test&` for recoverable
assertions. No shared fixture is supplied: per-case fixtures remain fresh.
Hook names have one accepted declaration each; overloaded duplicates are rejected.

A failed suite setup, including soft assertion failures, prevents that suite's
bodies and per-case hooks. Each otherwise executable case becomes skipped with
reason `suite setup failed`, without constructing its fixture. Suite cleanup is
still attempted exactly once. An ordinary setup failure does not suppress other
suites; suite state resets before moving on. Suite cleanup failure returns status
1 even if every ordinary case passed. Later successful hooks cannot erase it.

Suite failures are standalone records carrying owned source identity and phase.
They share the bounded failure/diagnostic arenas, but consume no case slots and
do not inflate failed-case totals. `suite_failures` counts failed hook executions;
several failed checks within one hook still count once. Hook assertions contribute
to the overall assertion count and a separate suite-assertion subtotal. Successful
hooks also own their identity metadata until the run ends; generated budgets
reserve both hook identities and possible setup-skip reasons.

`run_suite_hook(..., executable: false)` performs no callback, metadata allocation,
or state reset. This establishes the no-executable-selection boundary for disabled
and filtered suites. Generated all-disabled suites now enforce this boundary;
filtered suites enforce the same boundary.

Suite cleanup is attempted after framework resource exhaustion too, but exhausted
storage cannot retain more diagnostics. A terminal resource error stops later
suites and returns status 2. Fatal process errors still have no cleanup guarantee.

```sh
python3 integration/fixtures/suite/verify.py /tmp/goosetest
```


## Disabled cases and display labels

Attach standalone metadata comments directly before a test declaration:

```goose
// @DisplayName("expired token with clock skew")
// @Disabled("pending clock skew support")
fn test_clock_skew(t: goosetest::Test&) {
    t.fail("not implemented");
}
```

Disabled cases keep their stable path/namespace/function identity and report a
skip with the decoded reason and optional display label. Labels need not be
unique and never replace identity. Reasons must contain at least one decoded
byte. Both metadata strings have a 1024-byte generation limit. Ordinary quoted
string escapes are decoded and safely re-encoded into generated source; terminal
controls are escaped again by the console renderer.

The disabled body and its requested fixture and per-case hooks remain in an
unreachable, typechecked execution path with the required assertion recovery
ancestor. Suite hooks in all-disabled suites also retain unreachable references.
Compiler errors in these paths still fail the build. None of these constructors,
bodies or hooks execute at runtime. A fixture-free disabled case does not invent
a fixture dependency. A nonempty all-disabled run returns status 0 with its real
skip count and no lifecycle side effects; an empty project remains an error.

In mixed suites, suite hooks run once for executable cases. Disabled cases retain
their declared reason even if suite setup fails; only executable cases receive
`suite setup failed`. No fixture or per-case hook runs for a disabled case.

Only `@DisplayName` and `@Disabled` are supported. `@Tag`, `@RepeatedTest`, unknown
annotations, empty disabled reasons and malformed metadata fail discovery.

```sh
python3 integration/fixtures/disabled/verify.py /tmp/goosetest
```


## Selection and fail-fast

The CLI audits and compiles the complete project before running the selected
cases. Excluded tests retain unreachable typechecked wrappers but create no case
or fixture; excluded-only suites run no hooks. Disabled selected cases remain
explicit skips. See [CLI selection](../CLI.md) for the shared literal-ID selector.

With fail-fast enabled, case finalization sets `fail_fast_stop` only after its
cleanup returns. Failed suite hooks also set it. The current suite still runs
its cleanup, and later executable cases become `NotRun` records with reason
`fail-fast`. Current-suite setup-blocked cases remain skips, and disabled cases
keep their explicit reason. The stop flag is never cleared by a later successful
cleanup. Ordinary failure status 1 takes precedence over not-run count; not-run
records without any failure cause status 2 rather than a false pass.
