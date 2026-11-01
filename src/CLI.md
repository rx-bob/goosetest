# CLI discovery and execution

Build with the pinned Goose v2026.3 compiler, from the repository root:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest list --project examples/basic
/tmp/goosetest check-mirror --project examples/basic
/tmp/goosetest --help
```

`main.build` links the filesystem, process, and artifact adapters. The importable assertion package
still has no native sidecar. The compiler is needed to build this executable;
list and check-mirror do not invoke it when inspecting a project.

`--project PATH` defaults to `.` and may precede the command. Paths containing
spaces are supported. Use `./` for paths beginning with `--`. Repeated options,
extra commands/positionals, missing or empty project values, and unknown options
fail with status 2 and usage text. `--help` alone or alongside valid arguments
returns 0 without opening the project. Invalid arguments still fail with help
present. Execution and selection options are described below.

Before discovery, the CLI reads only `<project>/goosetest.json`. A missing file
keeps legacy `src`/`test`/`integration` discovery. Existing files must be valid
version 1 JSON with unique object keys, known fields, bounded target/root/pair
lists, valid target names and lexical project-relative paths. Malformed config
exits 2; it never falls back to legacy behavior. A valid config selects its
explicit test roots and exclusions. Test roots admit only `*_test.goose` files;
helper `.goose` files and `.goose.data` sidecars are ignored. Exclusions match
exact project-relative files or slash-terminated directory prefixes and are
applied before opening files or descending. Excluded entries count as inspected
entries, but excluded contents do not consume source bytes. Missing configured
roots fail validation.

Targets with `mirror.policy: "strict"` audit each declared source/tests pair
using paths relative to those roots. Targets with `mirror.policy: "off"` do not
scan source roots and skip mirror enforcement; they still parse admitted test
suites and reject malformed suites. `check-mirror` reports that enforcement is
disabled and exits 2 when no target enables strict mirroring. Mirror counts are
file correspondence, not source coverage claims.

All commands use the same complete [project validation](discovery/MIRRORS.md):
filesystem scan, bidirectional unit audit, integration admission and declaration
validation. A layout failure reports all missing/orphaned/bad-name records before
syntax parsing. Syntax failures retain their path, line and column. Empty suites
and projects fail. No partial listing appears on failure.

Successful output goes to stdout; failures and usage diagnostics go to stderr.
Status 0 means a valid list/audit/help request. Status 2 means invalid usage,
layout, read, discovery or resource failure. Status 1 reports executed assertion failures. Failure output explicitly says discovery is incomplete.

## Configured projects

Place one version 1 `goosetest.json` at the project root. This minimal form keeps
the test root at its existing path and disables source mirror checks:

```json
{
  "version": 1,
  "targets": [{
    "name": "core",
    "entry": "goosetest_core.goose",
    "tests": [{"path": "tests/request", "kind": "unit"}],
    "mirror": {"policy": "off", "pairs": []}
  }]
}
```

The authored entry imports `goosetest_generated.core.runner`. A `core` test ID
starts with `core::`; source modules do not need to move under `src/`.
For a consumer beside the goosetest checkout, the complete core entry is:

```goose
import goosetest from "../goosetest";
import goosetest_generated.core.runner;

fn main() { exit(goosetest_generated::run_all()); }
```

For strict unit correspondence, configure one exact pair per unit root:

```json
{
  "version": 1,
  "targets": [{
    "name": "core",
    "entry": "goosetest_core.goose",
    "tests": [{"path": "tests/request", "kind": "unit"}],
    "mirror": {
      "policy": "strict",
      "pairs": [{"source": "src/request", "tests": "tests/request"}]
    }
  }]
}
```

Strict pairs compare relative module stems; test roots must be unit roots. Every
unit root needs one pair. Integration roots do not have pairs. `check-mirror`
reports disabled enforcement and exits 2 for an `off` target; it never presents
an empty correspondence list as coverage.

Use distinct targets when native dependencies differ. Each entry has its own
optional adjacent sidecar (`goosetest_core.build`, `goosetest_database.build`):

```json
{
  "version": 1,
  "targets": [
    {"name": "core", "entry": "goosetest_core.goose",
     "tests": [{"path": "tests/core", "kind": "unit"}],
     "mirror": {"policy": "off", "pairs": []}},
    {"name": "database", "entry": "goosetest_database.goose",
     "tests": [{"path": "tests/database", "kind": "integration"}],
     "mirror": {"policy": "off", "pairs": []}}
  ]
}
```

For example, `goosetest_database.build` can own
`c_sources = ["db/adapter.c"]` while `goosetest_core.build` lists only core
sources. Selecting `core` excludes the database root, entry and sidecar from
discovery and compilation. Dependencies imported by the selected entry or its
shared helpers still belong to that target's build; place helpers deliberately
when their imports are optional.

`goosetest_core.build`:

```text
c_sources = ["native/core.c"];
```

`goosetest_database.build`:

```text
c_sources = ["db/adapter.c"];
```

```sh
goosetest list --project . --target core
goosetest test --project . --target core --profile debug --offline
goosetest test --project . --target core --profile optimized --offline
goosetest test --project . --target all --fail-fast
```

`--target NAME` is repeatable; omission and `--target all` select every target
in bytewise name order, and `all` cannot be combined with a name. A filter never
narrows syntax or type checking inside a selected target. A selected target with
matching cases builds the full target; a target with no matches is skipped when
another selected target has matches. If the entire selection matches zero cases,
the command exits 2. See [discovery roots](discovery/README.md),
[mirror policy](discovery/MIRRORS.md), and
[artifact ownership](generation/ARTIFACTS.md).

## Output contract

Listing follows sorted relative paths and declaration order. Each case includes
unit/integration kind, stable `<path>::<namespace>::<function>` identity and
`path:line:column`. Recognized display names and disabled reasons appear on
indented following lines. Backslashes are doubled; control bytes are escaped as
`\xNN` so decoded metadata cannot create fake rows. Case IDs never depend on labels.
The summary counts all discovered, executable and disabled cases; listing does
not execute them. Configured case IDs start with `<target>::`; legacy IDs remain
`<path>::<namespace>::<function>`. A disabled-only project remains valid.

`check-mirror` prints each successful correspondence and matched/missing/orphaned
counts, bad-filename count and independent integration-suite count. These measure
file correspondence, not statement, branch or behavioral coverage. Both commands
are deterministic and write no project artifacts.

The help text lists finite filesystem and syntax defaults. For accounting details,
see [inventory limits](discovery/README.md) and [syntax limits](discovery/SYNTAX.md).
The CLI additionally caps the explicit project argument at 4096 bytes. Reports are
rendered one record at a time rather than accumulating another whole-project arena.

## Reproducible checks

The process matrix uses Ruby only as the temporary parent/process launcher,
with an independent Goose oracle that uses builtin assertions,
independent of framework assertions. Run as an unprivileged user for permission
fixtures. Choose build/cache paths outside the inspected project:

```sh
export GOOSE_HOME=/tmp/goosetest-cli-cache
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest test --project . --suite unit
goose build --debug test_support/oracles/cli_test.goose -o /tmp/goosetest-cli-oracle
ruby integration/fixtures/cli/verify.rb /tmp/goosetest /tmp/goosetest-cli-oracle
goosefmt check --config .goosefmt.toml main.goose src/arguments.goose src/cli.goose \
    src/cli_output.goose test/arguments_test.goose test/cli_test.goose \
    test_support/oracles/cli_test.goose
```

Expected: the generated unit suite and CLI process checks both exit 0. Checks
cover exact listing/audit bytes, control metadata, argument ownership/errors,
actual child statuses, repeated/default-cwd/explicit-project output, the basic
example, rename diagnostics, malformed/empty suites, helper filenames, empty or
missing roots, unreadable files and file budgets. Project snapshots compare
entries, types, modes, sizes, content hashes and modification times (not access
times). Invalid production code and enabled write-sentinel bodies remain untouched;
the parent always removes its disposable fixtures after success or failure.

## One-command execution

`goosetest test --project PATH` validates the selected inventory, generates all
modules in memory, publishes them, builds the authored entry with
`goose build --debug`, and executes the generated test binary. Both child stages
use the project directory. Legacy projects use `goosetest_root.goose` and
`goosetest_generated/tests` and retain their original unqualified case IDs.
Configured projects select targets with repeatable `--target NAME`; omission and
`--target all` select all targets, and names run in bytewise order. `all` cannot be
combined with names. Only selected roots are scanned, and all selected targets
pass discovery and syntax preflight before listing or compilation. Configured IDs
include the target, such as `core::tests/core/path_test.goose::path_test::test_decode`.
For target `core`, author `goosetest_core.goose` to import
`goosetest_generated.core.runner` and exit with
`goosetest_generated::run_all()`. Its binary and completion record live under
`goosetest_generated/core/`. A valid selected target with no filter matches is
reported as selection-excluded and is not compiled when another selected target
has matches; a selection with no matches anywhere exits 2. `--suite` classifies
configured roots as unit or integration independently of mirror policy.
Compiler and test stdout/stderr are inherited.

Multi-target runs print a target/profile header before each target and a sorted
target summary at the end. The summary distinguishes passed, assertion failure,
incomplete, all-disabled, selection-excluded, and not-run targets. Without
`--fail-fast`, an assertion failure does not prevent later targets from running;
a compiler or runtime failure continues only when its child was reaped and cleanup
succeeded. `--fail-fast` stops after the first nonzero target result and marks
remaining selected targets `NOT RUN`. Cancellation stops immediately and returns
130 or 143. Aggregate status is cancellation first, then status 2, then status 1,
otherwise 0.

`--compiler PATH` defaults to `goose` through PATH. `test --profile debug|optimized`
defaults to `debug`; debug passes `-O0 --debug`, while optimized passes `-O2`
without debug checks. `--offline` passes Goose's offline flag and is opt-in.
Compiler arguments are passed literally without a shell. An explicit relative path
containing `/` is relative to the project directory; use an absolute path when
invoking from elsewhere. `--compile-timeout-seconds N` and
`--run-timeout-seconds N` each default to 120, accept integers 1..86400, and use
one second termination grace. These flags require `test`.

`--cache-root PATH` is also test-only. Relative paths resolve from the project;
without it, the base is `goosetest_generated/cache`. The compiler child receives
`GOOSE_HOME=<base>/<target-or-default>/<debug-or-optimized>`. Goosetest creates
that directory only during `test`, preserves inherited environment variables,
and leaves the caller and test binary `GOOSE_HOME` unchanged. Native cache contents
are never pruned as generated sources. Separate project executions sharing one
cache root are unsupported. Each invocation still builds its test binary.
With `--offline`, a cold cache missing a dependency fails with status 2 and never
reuses an older test binary.

Status 0 means completed passing tests, 1 means ordinary assertion failures,
and 2 means usage, validation, generation, artifacts, compiler, fatal runtime,
process, deadline or incomplete execution. Cancellation preserves 128+signal.
Generated execution writes a completion record after reporting; missing or
mismatched evidence rejects early `exit(0)` and `exit(1)`. This detects accidental
premature termination, not deliberately forged results by project code.

Each selected target compiles and runs as its own child process, so native globals
start fresh between targets. Cases within one target share that process and its
state. Put a hazardous suite in its own target when it needs process isolation;
goosetest does not reset state between individual cases or suites. A fatal child
failure may be followed by another target only after its owned process group has
been cleaned up and the direct child reaped; cleanup failure stops the run.
This boundary does not clean detached descendants, external services, or shared
database state. Keep disposable resource setup in authored target code and do not
point test fixtures at a shared production database. Framework hooks are not run
after a target is terminated by a deadline, cancellation, or fatal process error.

The authored entry remains untouched. The runner creates `goosetest_generated/`
with an ownership marker and manifest, or reuses a directory with valid ownership
metadata. Configured targets use an owned target subdirectory. Preexisting unowned
directories and symlinks fail without deletion. A nonblocking exclusive directory lock spans publication,
compilation, execution, and child cleanup. Concurrent runs fail with status 2;
closing the descriptor or process death releases the lock without stale lockfiles.

Generated sources publish atomically, preserving unchanged bytes and modification
times. Dependencies publish before `runner.goose`. A union manifest records claimed
files before writes, allowing regeneration after interruption. Only previously
manifested obsolete files are removed; unknown user files remain untouched.
Old executable and completion files are removed before every build. No successful
result or binary is cached. Failed writes or builds never start the test binary.
Sources remain available for inspection after failure and are disposable.

The checked-in basic snapshot includes ownership metadata, so it supports repeated
CLI runs. Older snapshots without a marker must be moved aside explicitly; the CLI
does not adopt them. Per-case fixtures and before_each/after_each hooks are
supported, as are before_all/after_all suite hooks; see
[lifecycle contracts](runtime/LIFECYCLE.md). Disabled cases compile without executing
and report skips with their reasons. Selection and fail-fast are described below.

Independent verification:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest test --project . --filter test/execution/
ruby integration/fixtures/execution/verify.rb /tmp/goosetest
```

The external verifier creates and removes its own projects and checks pass/fail,
next-case continuation, compiler failure, fatal checks, early exits, empty/audit/
generation rejection, stale binary prevention, project-relative resources, missing
compiler/output, compile/run deadlines, and cancellation.


The generated runtime report starts with `goosetest results`, after compiler
output. It includes declaration locations, stable IDs, display names, escaped
phase diagnostics, and finalized-case totals. See [console reporting](reporting/README.md)
for not-run/filtered accounting and the plain ASCII escaping contract.


## Selection and fail-fast

`--filter TEXT` is a literal, case-sensitive substring match against the complete
stable ID (`path::namespace::function`); it is not a regular expression or a display
label match. `--suite unit|integration|all` limits the test-root kind and defaults
to `all`. Both options apply identically to `list` and `test`, after a complete
layout/metadata audit. An empty filter matches all IDs. Filters are owned UTF-8/raw
argument bytes bounded at 4096 bytes; characters such as `*`, `[` and `.` have
no special matching syntax. A value beginning with `--` is still literal filter
text when it follows `--filter`.

```sh
/tmp/goosetest list --project examples/basic --filter '::test_addition'
/tmp/goosetest test --project examples/basic --suite unit --filter calculator
/tmp/goosetest test --project examples/basic --fail-fast
```

An empty selection returns status 2 with `selection matched zero cases`, before
writing artifacts or compiling. A nonempty disabled-only selection compiles and
returns status 0 with skips and no hook/fixture side effects. Explicit selection
listing reports selected executable/disabled counts and excluded count. Display
labels never affect matching. `check-mirror` rejects selector flags and always
audits the whole project; `--fail-fast` is accepted only by `test`.

Execution always compiles every discovered test, including tests excluded by
kind or filter. Excluded code and its relevant fixture/hook references remain
in typechecked unreachable paths. Selection cannot hide missing mirrors,
malformed metadata, unsupported syntax, or compiler errors. Excluded cases add
to the filtered count and do not become skipped or consume case records.

`--fail-fast` stops later executable case bodies after an ordinary case or suite
hook failure. Current-case cleanup finishes first; current-suite cleanup still
runs once, including after failed suite setup. A cleanup failure itself can
trigger the stop. Future suites run no hooks. Later selected executable cases
receive `NOT RUN` with reason `fail-fast`, distinct from filtered exclusions,
explicit disabled skips, and current-suite `suite setup failed` skips. Disabled
selected cases retain their skip reason even after a stop. Status remains 1;
resource/process errors still return 2. Without the flag, ordinary failures do
not prevent later cases or suites from running.

The independent process matrix is
`ruby integration/fixtures/selection/verify.rb /tmp/goosetest`.
