# Plain-text reporting

Import the public `goosetest` facade and call
`reporting::report(results, selected_case_count)` after execution and cleanup.
The facade intentionally exposes the qualified `reporting` namespace; generated
runners use this same entry point, including self-hosting.
The reporter also works with the independent explicit runtime harness; the facade imports the renderer but performs no output until called and links no native adapters.

`reporting::render(results, selected_case_count) { chunk => ... }` emits the same
bytes to a synchronous callback. Chunks are ephemeral slices; consume or copy them
inside the callback. Production writes chunks to stdout without retaining the
whole report. Escaped text chunks are at most 4096 bytes; sorting retains one
integer index per finalized case. The renderer neither mutates results nor runs
cleanup or assertions.

Case outcomes appear once, ordered by source path, namespace, declaration line,
and function name. Display/record contents break ties for explicit harnesses
that reuse identities. Stable IDs and source locations accompany each outcome;
the header states that locations identify test declarations, not exact failing
assertions. Display names and skip reasons appear beneath their case.

A separate failure section labels setup, test and cleanup diagnostics. Suite
setup/cleanup records appear in a separate suite-hook section. Totals count case
outcomes once, regardless of how many phases failed. Standalone suite-hook
errors carry their own source identity and count failed hook executions, not
individual checks or extra failed cases. Case-associated suite-phase diagnostics
from explicit harnesses remain renderable separately from ordinary phases.

Passed/failed/skipped/error and assertion totals are derived from finalized case
records, with the completed suite-hook assertion subtotal added. `not run` includes explicit NotRun records plus selected cases without a record; filtered count
is reported separately and must not be included in selected count. A negative
selected count defaults to the number of retained records, so explicit harnesses
must pass the intended selected count to expose cases never reserved. Generated
runners always pass their complete manifest case count. An active reserved case
is not shown as a finalized outcome. Active, empty, resource-error, missing-case,
or inconsistent-count reports explicitly say execution is incomplete.

The reporter does not change exit policy: callers return `goosetest::run_status`;
generated roots already do so. Explicit fail-fast stops are named in the report
and preserve ordinary failure status 1. A summary is not a substitute for process status.
For example, stopped-after-failure runs may show not-run cases with status 1.
Compiler stdout/stderr remains inherited; the `goosetest results` header separates
framework output from compiler messages. Fatal process failures cannot render
records from a dead process and remain the CLI execution stage's responsibility.

All metadata and diagnostic bytes outside printable ASCII, including newline,
ESC, DEL, C1 and UTF-8 bytes, are escaped as `\xNN`; backslashes are doubled.
Only renderer-authored newlines create output rows. Diagnostics currently retain
flattened text, so their embedded formatting newlines are escaped too: a user
message cannot inject a fake outcome or terminal control sequence. This baseline
requires no color support or terminal library.

Verification:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest test --project . --filter test/reporting/
goose build --debug test_support/oracles/reporting_test.goose -o /tmp/goosetest-reporting
python3 integration/fixtures/reporting/verify.py /tmp/goosetest-reporting
```

The independent six-case harness reports 5 passed/1 skipped/status 0 normally,
and 4 passed/1 failed/1 skipped/status 1 after changing the viewer expectation.
Additional modes exercise mixed phase failures, filtering, not-run counts and
incomplete execution. The harness uses the explicit `skip_case` runtime API;
generated disabled cases now share that API.
