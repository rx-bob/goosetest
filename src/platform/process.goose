// Canonical synchronous process boundary for the single-threaded macOS CLI.
namespace process;

enum Outcome {
    Exited,
    LaunchFailed,
    Signaled,
    Cancelled,
    Deadline,
    SystemError,
    InvalidInput
}
struct ProcessResult {
    outcome: Outcome = Outcome.InvalidInput,
    exit_code: i64 = - 1,
    signal: i64 = 0,
    native_error: i64 = 0,
    pid: i64 = 0,
    reaped: bool = false,
    cleanup_error: i64 = 0,
}
struct Limits {
    deadline_ms: i64 = 120000,
    grace_ms: i64 = 1000,
}
// All-i64 flat ABI. Native code initializes every field on every return path.
struct NativeResult {
    kind: i64 = 6,
    exit_code: i64 = - 1,
    signal: i64 = 0,
    error: i64 = 0,
    pid: i64 = 0,
    reaped: i64 = 0,
    cleanup_error: i64 = 0,
}

extern "gt_process_run" fn native_run(
    argv: const u8[:], cwd: const u8[:], deadline_ms: i64, grace_ms: i64, result: NativeResult&
);

// argv includes executable at index zero; no shell interpretation or implicit shell fallback.
fn run(argv: const u8[:][:], cwd: u8[:], limits: Limits = Limits {
    }) -> ProcessResult {
    if argv.len == 0 || argv.len > 256 || cwd.len == 0 || cwd.len > 4096
        || limits.deadline_ms <= 0 || limits.deadline_ms > 86400000
        || limits.grace_ms < 0 || limits.grace_ms > 60000 {
        return ProcessResult {
        };
    }
    var packed: u8[>..] = [];
    for value,
    index in argv {
        if (index == 0 && value.len == 0) || value.len >= 65536 - packed.len {
            return ProcessResult {
            };
        }
        for byte in value {
            if byte == 0 {
                return ProcessResult {
                };
            }
        }
        packed.append(value);
        packed.push(0);
    }
    for byte in cwd {
        if byte == 0 {
            return ProcessResult {
            };
        }
    }
    var native = NativeResult {
    };
    native_run(packed, cwd, limits.deadline_ms, limits.grace_ms, native);
    return decode(native);
}

fn decode(native: NativeResult) -> ProcessResult {
    var outcome = Outcome.SystemError;
    if native.kind == 0 {
        outcome = Outcome.Exited;
    }
    else if native.kind == 1 {
        outcome = Outcome.LaunchFailed;
    }
    else if native.kind == 2 {
        outcome = Outcome.Signaled;
    }
    else if native.kind == 3 {
        outcome = Outcome.Cancelled;
    }
    else if native.kind == 4 {
        outcome = Outcome.Deadline;
    }
    else if native.kind == 6 {
        outcome = Outcome.InvalidInput;
    }
    return ProcessResult {
        outcome: outcome,
        exit_code: native.exit_code,
        signal: native.signal,
        native_error: native.error,
        pid: native.pid,
        reaped: native.reaped != 0,
        cleanup_error: native.cleanup_error,
    };
}
