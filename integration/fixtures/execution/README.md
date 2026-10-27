# CLI execution oracle

From the repository root, build the CLI and pass its executable to the verifier:

```sh
goose build --debug main.goose -o /tmp/goosetest
python3 integration/fixtures/execution/verify.py /tmp/goosetest
```

The Python parent checks actual process statuses and output for successful tests,
assertion failures, build failures, aborts, explicit exits, invalid layouts,
generation errors, missing compilers, and compilers that produce no executable.

Compilation and execution each have deadline and SIGINT scenarios. A native
fixture records its own PID and a descendant PID, ignores graceful termination,
and has a finite 30-second alarm fallback. The oracle waits for readiness before
cancellation and checks both recorded processes independently after termination.
Direct children must disappear; an adopted descendant may briefly be a non-running
zombie until the operating system reaps it. Polling has a generous bounded deadline;
the test does not assert scheduler performance.

Each scenario starts with a previously passing executable. During interruption,
a marker proves that stale code did not run. Deadlines must exit 2 with the stage
named in the diagnostic; SIGINT must exit 130 with signal 2 and an incomplete-run
diagnostic. A successful retry in the same directory proves ownership was released.
The parent has emergency cleanup for recorded processes if a check fails.
