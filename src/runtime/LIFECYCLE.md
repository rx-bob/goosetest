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
errors. Hooks are optional. Suite hooks are described below; disabled execution
and selection remain separate stories.

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
and filtered suites. End-to-end disabled/filter generation arrives in E4.S3/E4.S4;
those unsupported requests still fail before execution today.

Suite cleanup is attempted after framework resource exhaustion too, but exhausted
storage cannot retain more diagnostics. A terminal resource error stops later
suites and returns status 2. Fatal process errors still have no cleanup guarantee.

```sh
python3 integration/fixtures/suite/verify.py /tmp/goosetest
```
