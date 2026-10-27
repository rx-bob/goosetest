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
errors. Hooks are optional. Suite hooks (`before_all`/`after_all`), disabled
execution, and selection remain separate stories.

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
