# Basic package consumer

This example imports the actual goosetest package. Its default tests all pass.
Use the pinned Goose v2026.3 compiler on macOS arm64; no native sidecar or
third-party runtime library is required.

From the repository root:

```sh
goose build --debug examples/basic/goosetest_root.goose -o /tmp/goosetest-basic
/tmp/goosetest-basic
```

Expected output and process status:

```text
PASS test/calculator_test.goose::calculator_test::test_addition (test/calculator_test.goose:8)
PASS test/calculator_test.goose::calculator_test::test_subtraction (test/calculator_test.goose:12)
PASS test/calculator_test.goose::calculator_test::test_zero_identity (test/calculator_test.goose:16)
Cases: 3 passed, 0 failed, 0 skipped, 0 errors
```

The executable exits 0. Build output comes from the compiler, separately from
the example's output above.

## Layout and package wiring

- `src/calculator.goose` contains production arithmetic.
- `test/calculator_test.goose` mirrors that module with ordinary namespaced
  `test_*(t: goosetest::Test&)` functions and direct imports.
- `goosetest_generated/` contains a checked-in deterministic generation snapshot.
  It owns result storage and calls every discovered case through the runtime.
- `bootstrap_root.goose` and `test_support/bootstrap.goose` retain the independent
  explicit harness used by the original package regression.
- `goosetest_root.goose` declares the package and propagates aggregate status
  through `exit(...)`.

The root's `import goosetest from "../..";` resolves relative to that file, not
the shell's working directory. In a separate project beside a goosetest checkout,
change the source to `"../goosetest"`. Subordinate files keep `import goosetest;`.
Do not copy the runtime into your application or reconstruct its package modules.

The generated snapshot keeps this example buildable from a clean checkout.
After adding or changing tests, regenerate from the complete audited manifest;
no root or registration list edit is needed. See the
[generation procedure](../../src/generation/README.md) for the transitional driver
and fresh-output workflow. The one-command execution CLI arrives in E3.S3.
Fixture parameters, lifecycle hooks and disabled execution are rejected by this
first generator until E4 supplies their semantics. Fixture-free tests and escaped
display labels are supported now.

## Assertions and failure behavior

Equality is **expected first**: `t.assert_eq(42, calculator::add(20, 22))`.
`assert_ne` takes the unexpected value first. Assertion messages are optional
except for `fail(message)`. Hard assertions record diagnostics, stop the current
case, and permit later cases to run. `check_eq` records a failure and continues
unless a storage budget is exhausted.

Goose builtin `assert`, `abort`, and runtime checks are fatal checks, not
recoverable test assertions. Use framework assertions for ordinary expectations.
This harness returns 1 for assertion failures and 2 for incomplete/resource-error
runs; it does not convert a fatal runtime abort into a normal case result.

The [runtime reference](../../integration/fixtures/runtime/README.md) explains
owned result storage, limits, diagnostics, and status codes. The small console
display here belongs to this example; the runtime itself does not print.

## External verification

The [package regression procedure](../../integration/fixtures/package/README.md)
copies this project outside the repository and verifies it from two working
directories. Its deliberately failing replacement suite is stored as `.goose.data`
and materialized only in that disposable copy. The default example is never edited
to introduce an intentional failure.

Check example style from the repository root:

```sh
goosefmt check --config .goosefmt.toml examples/basic
```

For automatic regeneration and execution, build the CLI and run:

```sh
goose build --debug main.goose -o /tmp/goosetest
/tmp/goosetest test --project examples/basic
```

The snapshot includes `.owner` and `.manifest` ownership metadata. Repeated runs
preserve unchanged generated source timestamps, prune obsolete listed modules,
and rebuild the executable. The authored root remains unchanged.
