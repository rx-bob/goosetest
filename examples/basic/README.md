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
PASS test_addition
PASS test_subtraction
PASS test_zero_identity
Cases: 3 passed, 0 failed, 0 skipped, 0 errors
```

The executable exits 0. Build output comes from the compiler, separately from
the example's output above.

## Layout and package wiring

- `src/calculator.goose` contains production arithmetic.
- `test/calculator_test.goose` mirrors that module with ordinary namespaced
  `test_*(t: goosetest::Test&)` functions and direct imports.
- `test_support/bootstrap.goose` owns result storage, explicitly executes three
  cases, and prints their results.
- `goosetest_root.goose` declares the package and propagates aggregate status
  through `exit(...)`.

The root's `import goosetest from "../..";` resolves relative to that file, not
the shell's working directory. In a separate project beside a goosetest checkout,
change the source to `"../goosetest"`. Subordinate files keep `import goosetest;`.
Do not copy the runtime into your application or reconstruct its package modules.

The explicit bootstrap is temporary: generated orchestration replaces it in E3.
Test files already use the planned discovered-function authoring model, with no
main function or registration list. Automatic discovery and fixture hooks are not
implemented by this example; their stories add them later. Production source and
ordinary test signatures can remain unchanged when the bootstrap is replaced.

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
