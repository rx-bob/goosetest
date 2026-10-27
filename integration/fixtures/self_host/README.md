# Repository self-host verification

Run from the repository root with the pinned Goose compiler and Python 3:

```sh
goose run scripts/verify.goose
```

Alternatively, run `python3 integration/fixtures/self_host/verify.py` directly.
The Goose entry point invokes that same independent verifier with a finite
one-hour deadline and preserves its process status.

The verifier builds the CLI into a temporary directory, then runs the repository's
strict mirror audit, lists every case, and executes the generated test runner.
A separate Python tokenizer reads real top-level `fn test_*` declarations from
`test/` and `integration/`, ignoring strings and comments. Listed IDs and passing
result IDs must match that inventory exactly. This detects missing registrations,
synthetic fixture discovery, skipped execution, duplicate rows, and omitted cases.

A disposable repository copy then receives one injected public `outer.fail` call
in `integration/self_host_test.goose`. The process must exit 1, report exactly that
case as failed with the injected diagnostic, and pass every other case. The original
source remains unchanged. This check is deliberately outside the runtime it judges.

The Python parent owns compiler caches, copied sources, and `TMPDIR`; it removes
these on completion or failure. Compiler and runner deadlines are 600 seconds;
each subprocess has a 900-second parent deadline. The CLI owns its generated
artifacts using its normal lifecycle. No installed binary is written by verification.

The authored `goosetest_root.goose` supplies the repository's native test adapters
and calls `goosetest_generated::run_all()`. Helpers and standalone compiler/runtime
oracles live under `test_support/`, outside the discovery roots. The old bootstrap
executables are not required to register the repository's tests.
