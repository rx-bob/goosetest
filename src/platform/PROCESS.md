# Native process boundary (E3.S2)

`process::run(argv, cwd, limits)` synchronously owns one child stage. `argv[0]` is
its executable; subsequent elements arrive literally, including empty strings,
spaces, quotes, dollar signs and semicolons. The child receives an explicit cwd,
inherited environment and stdin/stdout/stderr. No pipes, capture buffers, shell
command construction or output parsing exist in the adapter.

The available baseline is macOS arm64 with Goose v2026.3, using `posix_spawn`,
`posix_spawn_file_actions_addchdir_np`, process groups and monotonic time. Other
platforms deliberately fail native compilation until a separate implementation is
verified. `src/platform/process.goose` is the sole canonical foreign declaration;
`native/process.c` is linked explicitly by executable `.build` sidecars, including
`main.build`. The public assertion facade imports neither module. The current CLI
still exposes only read-only commands; execution wiring comes in E3.S3.

## Arguments and limits

The public argv type is `(const u8[:])[:]`. Give mixed mutable/string-literal
arrays an explicit `const u8[:][N]` element type on this compiler. Nested slices
cannot cross its FFI, so Goose copies arguments into a bounded NUL-delimited
arena; native code copies them into native argv storage. A flat all-i64 native
result struct is translated into the named public result. No borrowed temporary
argv/cwd data survives the call.

| Bound | Value |
| --- | ---: |
| Arguments including executable | 256 |
| Packed argument bytes including one NUL per argument | 65536 |
| Explicit cwd bytes | 4096 |
| Inherited PATH bytes when searching a bare executable | 65536 |
| Constructed PATH candidate bytes | 4096 |
| Default deadline | 120000 ms |
| Allowed deadline | 1–86400000 ms |
| Default termination grace | 1000 ms |
| Allowed grace | 0–60000 ms |
| Supervision poll interval | 10 ms |
| Zombie-only diagnostic snapshot | fewer than 4096 process records |

Embedded NULs, empty executable/cwd, and invalid limits are rejected. Other argv
entries may be empty. A path containing `/` is used directly; relative paths are
resolved in the child cwd. Bare executable names use explicit bounded PATH search;
unset PATH defaults to `/usr/bin:/bin`, and empty components mean the child cwd.
Each candidate checks the stage deadline and pending cancellation. Native launch
errors preserve errno, including permission and executable-format failures.

The implementation deliberately does **not** call `posix_spawnp`: a local probe
proved that macOS falls back to `/bin/sh` for executable text with no recognized
format. Direct `posix_spawn` preserves `ENOEXEC`; regression tests cover both an
absolute path and bare-name PATH search. Valid shebang executables still follow
the OS's normal executable semantics.

## Result contract

`ProcessResult` separates:

- `Exited`: `exit_code` is the actual 0–255 status, including nonzero child exits.
- `LaunchFailed`: no stage was launched; `native_error` is the launch errno.
- `Signaled`: `signal` identifies the child's terminating signal.
- `Cancelled`: SIGINT or SIGTERM interrupted ownership; `signal` is the received
  cancellation signal, even if the child handles it and exits 0.
- `Deadline`: the stage budget expired, including during PATH lookup.
- `SystemError`: supervision/setup/restoration failed.
- `InvalidInput`: argument or limit validation failed before launch.

`exit_code` is -1 unless a normal exit was observed. `pid` is zero when no child
was created. `reaped` records successful direct-child `waitpid`; `cleanup_error`
preserves signaling, reaping or signal-restoration failure independently of the
original timeout/cancellation cause. A caller must not treat cleanup errors as
successful execution. The process boundary does not map these results to CLI
exit codes or classify a test assertion failure; that belongs to E3.S3.

## Ownership, interruption and cleanup

This is a serial, single-threaded CLI API, not a general-purpose concurrent
subprocess library. The CLI must exclusively own waiting for its stage. The
adapter blocks SIGINT/SIGTERM/SIGCHLD during setup, installs minimal cancellation
handlers, and gives the child a new process group, empty signal mask and default
common terminal-signal dispositions. Parent cancellation is unblocked during
supervision; SIGCHLD remains blocked so an existing handler cannot steal the wait.
Preexisting SIGCHLD ignore/automatic-reaping configurations are rejected. Previous
signal handlers and mask are restored on every return path. Other descriptors
are closed in the child using macOS close-on-exec spawn behavior; standard streams
remain inherited when open.

Deadline expiry sends TERM to the whole group. Cancellation forwards its actual
INT/TERM signal. After the configured grace period, KILL targets the entire group,
even if the leader has already exited. A normal leader exit also triggers final
group cleanup so a background child cannot outlive the stage unnoticed. The leader
is observed with `waitid(WNOWAIT)` and kept unreaped until group cleanup, preventing
its PID/group identity from being reused. `waitpid` then reaps the direct child.

macOS returns EPERM when signaling a group containing only zombies. A bounded
`sysctl(KERN_PROC_PGRP)` snapshot suppresses that error only when the retained
leader is present and **every** returned member is a zombie. Inaccessible data,
capacity exhaustion, or a live member preserves the error. This avoids confusing
already-dead children with a real permission failure.

The deadline begins before launch. Normal tests complete within deadline plus
grace and polling/scheduling overhead. This is not a hard real-time guarantee:
synchronous OS launch, uninterruptible kernel work, scheduling delays or an OS
permission refusal can delay cleanup. The adapter waits to reap its direct child
rather than returning a falsely completed stage. macOS cannot reap grandchildren;
the group receives termination, while their eventual reaping belongs to their
parent/system. Deliberately detached descendants and processes that change
credentials beyond the caller's signaling permission are outside group containment.
No per-test crash isolation or general sandbox is claimed.

## Reproducible verification

From the repository root with the pinned compiler and Apple command-line tools:

```sh
export GOOSE_HOME=/tmp/goosetest-process-cache
clang -std=c11 -Wall -Wextra -Werror integration/fixtures/process/child.c -o /tmp/goosetest-process-child
goose build --debug test/process_bootstrap.goose -o /tmp/goosetest-process-unit
goose build --debug integration/process_test.goose -o /tmp/goosetest-process-driver
python3 integration/fixtures/process/verify.py /tmp/goosetest-process-driver \
    /tmp/goosetest-process-child /tmp/goosetest-process-unit
goosefmt check --config .goosefmt.toml src/platform/process.goose \
    test/platform/process_test.goose test/process_bootstrap.goose \
    test_support/process.goose integration/process_test.goose
clang -std=c11 -Wall -Wextra -Werror -fsyntax-only native/process.c
```

Expected: `process unit tests passed` and `process lifecycle tests passed`, exit 0.
Tests use builtin assertions and a parent-owned temporary directory. The child
fixture verifies literal argv/cwd and inherited streams; the matrix checks exit
0/7/127, missing executable/cwd, ENOEXEC without shell fallback, signal termination,
exact/over argument budgets, deadline during PATH search, hung children, groups
whose leader dies before its descendant, normal-exit descendants, and cancellation
whose handler exits 0. Native test-only observers check `waitpid` returns ECHILD
and prior handlers/masks are restored. Python checks recorded PIDs externally;
direct children must disappear and descendants must be absent or non-running
zombies. The parent has emergency cleanup for failed checks.

A separate basic-consumer build/run plus symbol inspection verifies no
`gt_process_*` or `gt_fs_*` symbols enter a runtime-only application. Neither test
observers nor purpose-built child fixtures are linked into the production adapter.
