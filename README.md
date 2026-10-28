# goosetest

Goose assertions and a test runner that discovers ordinary `test_*` functions.
Unit tests mirror production modules; integration suites cover behavior across
modules. Tests need no registration list.

The supported baseline is **Goose v2026.3 on macOS arm64**. Install its `goose`
compiler, Apple command-line tools (`clang`), Python 3, `goosefmt`, and Task on
`PATH`. Run verification as an unprivileged user: permission fixtures reject root.
See [compiler compatibility](docs/compatibility.md) for the recorded toolchain.

## Build and verify

From the repository root:

```sh
task build
task example
task test
task check
build/goosetest --help
```

`build` creates the debug CLI at `build/goosetest`. `example` discovers, builds,
and runs the passing [basic consumer](examples/basic/README.md). `test` runs the
self-hosted suite and independent process-level failure checks. `check` checks
shipping and representative generated Goose sources. Task delegates automation
to Goose scripts in `scripts/`; these verification targets do not install or publish a package.

The [isolated pretty-goose consumer](docs/adopting_pretty_goose.md) demonstrates
lexer and formatter adoption against preserved production snapshots. Its original
repository and test commands remain unchanged.

## Install the CLI and share the package

Goosetest has two parts: the CLI executable and the source package imported by
your tests. From this checkout, build and install the CLI with:

```sh
task install
```

This builds the current sources and installs `goosetest` with executable permissions
into `~/.local/bin`. Ensure that directory is on `PATH`. To choose another prefix:

```sh
GOOSETEST_INSTALL_PREFIX=/your/install/prefix task install
```

The executable is installed into `<prefix>/bin/goosetest`. Installation does not
copy the source package or alter consumer projects. Keep the installed CLI and
the source package used by your projects at the same revision.

For a project beside this checkout, create its `goosetest_root.goose` once:

```goose
import goosetest from "../goosetest";

import goosetest_generated.runner;

fn main() {
    exit(goosetest_generated::run_all());
}
```

Paths are relative to that root file. Tests use `import goosetest;` and live in
`test/`, mirroring production modules in `src/`; independent suites live in
`integration/`. From the consumer project, run:

```sh
goosetest test --project .
```

To distribute the source package, publish this repository and tag a release.
Consumers can replace the local dependency declaration with:

```goose
import goosetest from "github.com/YOUR_ACCOUNT/goosetest@v0.1.0";
```

Replace `YOUR_ACCOUNT` and the ref with your actual published repository and
release. This is a syntax example, not an existing published package URL. Goose
requires no registry registration or additional package manifest: the repository
already provides `goosetest.goose` and its imported modules. Pin a full commit hash
instead of a movable tag for reproducible builds. The supported compiler and
platform remain Goose v2026.3 on macOS arm64.

## Use a local checkout

Declare the local dependency once in your authored `goosetest_root.goose`.
This is the maintained basic example root:

```goose
// Authored package root stays stable while discovery refreshes generated orchestration.
import goosetest from "../..";

import goosetest_generated.runner;

fn main() {
    exit(goosetest_generated::run_all());
}
```

The source path resolves relative to the root file. The maintained
[basic root](examples/basic/goosetest_root.goose) uses `"../.."` to reach this
checkout. For a separate consumer beside a goosetest checkout, use
`import goosetest from "../goosetest";` instead. Subordinate suites use
`import goosetest;`. No registry install or
unverified repository URL is required. Keep your local dependency at the revision
you intend to use.

An optional `goosetest_root.build` can declare your test executable's native
sources, for example `c_sources = ["native/test_adapter.c"];`. Paths are relative
to that authored sidecar. Runtime-only consumers need no goosetest native adapter.
The generator preserves the root and its sidecar; it never reconstructs your
production entry point or package declarations.

Use the built CLI against your project:

```sh
/path/to/goosetest/build/goosetest check-mirror --project /path/to/project
/path/to/goosetest/build/goosetest list --project /path/to/project
/path/to/goosetest/build/goosetest test --project /path/to/project
```

`list` and `check-mirror` do not compile or execute tests. `test` audits, generates,
builds with `goose build --debug`, and executes the authored root. The CLI owns
its files in `goosetest_generated/`; do not hand-edit those files.

## Author tests

```text
src/calculator.goose           production module
test/calculator_test.goose     matching unit suite
integration/workflow_test.goose  independent integration suite
test_support/                 helper modules outside discovery
goosetest_root.goose           authored test entry point
```

Every `.goose` module under `src/` needs a corresponding `_test.goose` under
`test/`, and every unit suite needs its production counterpart. Integration suites
need no unit mirror. Each suite declares a namespace and at least one test. Keep
helpers outside the scanned roots; store invalid source fixtures as `.goose.data`
and materialize them only in disposable projects. This strict layout audit is not
a code-coverage measurement.

This test comes from the compiled [calculator suite](examples/basic/test/calculator_test.goose):

```goose
fn test_addition(t: goosetest::Test&) {
    t.assert_eq(42, calculator::add(20, 22));
}
```

Assertions are expected-first: `assert_eq(expected, actual)`,
`assert_ne(unexpected, actual)`, `assert_contains(fragment, text)`,
`assert_near(expected, actual, absolute_tolerance)`, and
`assert_struct_eq(expected, actual)`. Also available: `assert_true`, `assert_false`,
`fail(message)`, and soft `check_eq`. Messages are optional except for `fail`.
Struct comparison reports unequal top-level fields; it is not recursive object
graph comparison. Containment compares bytes, and near comparison uses a finite,
nonnegative absolute tolerance. See the [assertion reference](integration/fixtures/runtime/README.md).

Hard framework assertions stop the current body or hook phase. `check_eq` records
a failure and continues unless a storage budget is exhausted. Goose builtin
`assert`, aborts, and native crashes are fatal process failures, not recoverable
framework assertions.

The maintained [integration suite](examples/basic/integration/arithmetic_test.goose)
shows fixture setup and cleanup without a unit mirror:

```goose
// Integration suites need no source mirror and can own fresh per-case fixtures.
namespace arithmetic_test;

import goosetest;
import src.calculator;

struct Fixture {
    initial: i64 = 40,
    current: i64 = 0
}

fn before_each(t: goosetest::Test&, fixture: Fixture&) {
    fixture.current = fixture.initial;
    t.assert_eq(40, fixture.current, "fresh fixture starts at forty");
}

fn after_each(t: goosetest::Test&, fixture: Fixture&) {
    t.assert_eq(fixture.initial, fixture.current, "round trip restores the starting value");
}

fn test_round_trip(t: goosetest::Test&, fixture: Fixture&) {
    fixture.current = calculator::add(fixture.current, 2);
    t.assert_eq(42, fixture.current);
    fixture.current = calculator::subtract(fixture.current, 2);
    t.assert_eq(40, fixture.current);
}
```

A test may request `f: Fixture&` after its context. Each such test constructs a
fresh `Fixture`; `before_each(f)` and `after_each(f)` surround its body. Hooks may
take a context first for assertions. Fixture-free tests construct no fixture and
run no per-case hooks. `before_all()` and `after_all()` surround a suite with
selected executable cases and may take a context. Cleanup is attempted after
recoverable setup/body failure; setup failure suppresses the body. Make partially
initialized fixtures safe to clean up. Process termination and fatal checks have
no cleanup guarantee. See the complete [lifecycle contract](src/runtime/LIFECYCLE.md).

Standalone `// @DisplayName("label")` and `// @Disabled("reason")` comments may
precede a test. Disabled bodies, fixtures, and per-case hooks remain typechecked
but do not execute; all-disabled suites run no suite hooks. Display labels never replace stable IDs: `path.goose::namespace::test_function`.

## Select cases and interpret results

```sh
build/goosetest list --project examples/basic --suite unit
build/goosetest test --project examples/basic --filter test_addition
build/goosetest test --project examples/basic --suite integration --fail-fast
```

`--filter` is a literal substring of the stable ID; `--suite` accepts `unit`,
`integration`, or `all`. Selection still audits and typechecks the whole project.
A test selection matching no cases exits 2. Fail-fast finishes current cleanup,
then reports remaining executable cases as not run. Excluded cases, disabled
skips, setup-blocked skips, and fail-fast omissions have distinct counts.

| Status | Meaning |
| --- | --- |
| 0 | Valid list/audit/help, or completed tests without failures; a nonempty all-disabled run may succeed. |
| 1 | Executed framework assertion or suite-hook failure. |
| 2 | Usage, discovery, generation, build, runtime abort, deadline, limit breach, or incomplete run. |
| 130 / 143 | SIGINT / SIGTERM cancellation propagated by the CLI. |

Compiler and run deadlines each default to 120 seconds, with one-second
termination grace. Override them using `--compile-timeout-seconds N` and
`--run-timeout-seconds N`, where N is 1–86400. `--compiler PATH` selects a compiler.
Reports identify the test declaration location, not an exact assertion source line.
See [architecture and finite budgets](docs/architecture.md) and [CLI details](src/CLI.md).

## Scope

Unsupported: tags, repetitions, parameterized cases, nested describe DSL,
contained-worker APIs, per-case crash isolation, parallel runs, property testing,
snapshots, watch mode, exporters, and unverified operating systems. The assertion
runtime uses Goose's standard library; CLI discovery, process management, and
artifact ownership use the macOS native boundary.

`poc/` is historical research, not a second supported implementation. Its syntax,
style, performance claims, and cleanup assumptions are not release guarantees.
Shipping checks exclude it and inert `.goose.data` inputs. Maintained examples,
shipping Goose sources, and representative generated output are checked instead.
