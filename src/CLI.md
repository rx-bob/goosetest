# CLI discovery and execution

Build with the pinned Goose v2026.3 compiler, from the repository root:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest list --project examples/basic
/tmp/goosetest check-mirror --project examples/basic
/tmp/goosetest --help
```

`main.build` links the filesystem, process, and fresh-artifact adapters. The importable assertion package
still has no native sidecar. The compiler is needed to build this executable;
list and check-mirror do not invoke it when inspecting a project.

`--project PATH` defaults to `.` and may precede the command. Paths containing
spaces are supported. Use `./` for paths beginning with `--`. Repeated options,
extra commands/positionals, missing or empty project values, and unknown options
fail with status 2 and usage text. `--help` alone or alongside valid arguments
returns 0 without opening the project. Invalid arguments still fail with help
present. Execution options are described below. Filters, exclusions and configuration files remain deferred.

All commands use the same complete [project validation](discovery/MIRRORS.md):
filesystem scan, bidirectional unit audit, integration admission and declaration
validation. A layout failure reports all missing/orphaned/bad-name records before
syntax parsing. Syntax failures retain their path, line and column. Empty suites
and projects fail. No partial listing appears on failure.

Successful output goes to stdout; failures and usage diagnostics go to stderr.
Status 0 means a valid list/audit/help request. Status 2 means invalid usage,
layout, read, discovery or resource failure. Status 1 reports executed assertion failures. Failure output explicitly says discovery is incomplete.

## Output contract

Listing follows sorted relative paths and declaration order. Each case includes
unit/integration kind, stable `<path>::<namespace>::<function>` identity and
`path:line:column`. Recognized display names and disabled reasons appear on
indented following lines. Backslashes are doubled; control bytes are escaped as
`\xNN` so decoded metadata cannot create fake rows. Case IDs never depend on labels.
The summary counts all discovered, executable and disabled cases; listing does
not execute them. A disabled-only project remains valid.

`check-mirror` prints each successful correspondence and matched/missing/orphaned
counts, bad-filename count and independent integration-suite count. These measure
file correspondence, not statement, branch or behavioral coverage. Both commands
are deterministic and write no project artifacts.

The help text lists finite filesystem and syntax defaults. For accounting details,
see [inventory limits](discovery/README.md) and [syntax limits](discovery/SYNTAX.md).
The CLI additionally caps the explicit project argument at 4096 bytes. Reports are
rendered one record at a time rather than accumulating another whole-project arena.

## Reproducible checks

The process matrix uses Python only as the temporary parent/process launcher,
with an independent Goose oracle that uses builtin assertions,
independent of framework assertions. Run as an unprivileged user for permission
fixtures. Choose build/cache paths outside the inspected project:

```sh
export GOOSE_HOME=/tmp/goosetest-cli-cache
goose build --debug main.goose -o /tmp/goosetest
goose build --debug test/cli_bootstrap.goose -o /tmp/goosetest-cli-unit
/tmp/goosetest-cli-unit
goose build --debug integration/cli_test.goose -o /tmp/goosetest-cli-oracle
python3 integration/fixtures/cli/verify.py /tmp/goosetest /tmp/goosetest-cli-oracle
goosefmt check --config .goosefmt.toml main.goose src/arguments.goose src/cli.goose \
    src/cli_output.goose test/arguments_test.goose test/cli_test.goose \
    test/cli_bootstrap.goose integration/cli_test.goose
```

Expected: `cli unit tests passed` and `cli process tests passed`, exit 0. Checks
cover exact listing/audit bytes, control metadata, argument ownership/errors,
actual child statuses, repeated/default-cwd/explicit-project output, the basic
example, rename diagnostics, malformed/empty suites, helper filenames, empty or
missing roots, unreadable files and file budgets. Project snapshots compare
entries, types, modes, sizes, content hashes and modification times (not access
times). Invalid production code and enabled write-sentinel bodies remain untouched;
the parent always removes its disposable fixtures after success or failure.

## One-command execution (E3.S3)

`goosetest test --project PATH` validates the complete inventory, generates all
modules in memory, writes them, builds `goosetest_root.goose` using
`goose build --debug`, and executes `./goosetest_generated/tests`. Both child
stages use the project directory. The authored root must import generated
`runner` and exit with `goosetest_generated::run_all()` as in the basic example.
Compiler and test stdout/stderr are inherited without capture.

`--compiler PATH` defaults to `goose` through PATH. An explicit relative path
containing `/` is relative to the project directory; use an absolute path when
invoking from elsewhere. `--compile-timeout-seconds N` and
`--run-timeout-seconds N` each default to 120, accept integers 1..86400, and use
one second termination grace. These flags require `test`.

Status 0 means completed passing tests, 1 means ordinary assertion failures,
and 2 means usage, validation, generation, artifacts, compiler, fatal runtime,
process, deadline or incomplete execution. Cancellation preserves 128+signal.
Generated execution writes a completion record after reporting; missing or
mismatched evidence rejects early `exit(0)` and `exit(1)`. This detects accidental
premature termination, not deliberately forged results by project code.

This incremental release requires **absent `goosetest_generated/`** and a regular
`goosetest_root.goose`. Existing directories, files and symlinks are refused;
nothing is overwritten or deleted. Generated source remains for inspection after
success or failure. For the checked-in example, use a disposable copy and remove
its generated snapshot there before invoking `test`. Owned regeneration, atomic
updates, pruning and repeated-run support are E3.S4. Fresh directories ensure old
executables cannot run after failed compilation. Fixtures, hooks, disabled
execution and selection remain E4; unsupported semantics fail before writing.

Independent verification:

```sh
goose build --debug test/execution_bootstrap.goose -o /tmp/goosetest-execution-unit
/tmp/goosetest-execution-unit
python3 integration/fixtures/execution/verify.py /tmp/goosetest
```

The external verifier creates and removes its own projects and checks pass/fail,
next-case continuation, compiler failure, fatal checks, early exits, empty/audit/
generation rejection, stale output refusal, project-relative resources, missing
compiler/output, compile/run deadlines, and cancellation.
