# Read-only CLI (E2.S4)

Build with the pinned Goose v2026.3 compiler, from the repository root:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest list --project examples/basic
/tmp/goosetest check-mirror --project examples/basic
/tmp/goosetest --help
```

`main.build` links only the filesystem adapter. The importable assertion package
still has no native sidecar. The compiler is needed to build this executable;
neither command invokes it when inspecting a project.

`--project PATH` defaults to `.` and may precede the command. Paths containing
spaces are supported. Use `./` for paths beginning with `--`. Repeated options,
extra commands/positionals, missing or empty project values, and unknown options
fail with status 2 and usage text. `--help` alone or alongside valid arguments
returns 0 without opening the project. Invalid arguments still fail with help
present. There are no execution, filter, exclusion or configuration-file options.

Both commands use the same complete [project validation](discovery/MIRRORS.md):
filesystem scan, bidirectional unit audit, integration admission and declaration
validation. A layout failure reports all missing/orphaned/bad-name records before
syntax parsing. Syntax failures retain their path, line and column. Empty suites
and projects fail. No partial listing appears on failure.

Successful output goes to stdout; failures and usage diagnostics go to stderr.
Status 0 means a valid list/audit/help request. Status 2 means invalid usage,
layout, read, discovery or resource failure. Status 1 remains reserved for future
executed assertion failures. Failure output explicitly says discovery is incomplete.

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
until the later native process story. Its Goose oracle uses builtin assertions,
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
