// Parent drives cancellation and verifies result records against external child observations.
import goosetest from "../..";
import goosetest.src.platform.process;
import goosetest.test_support.process;

import os;
import std;

fn main() {
    let values = args();
    assert(values.len >= 5);
    var limits = process::Limits {
        deadline_ms: 5000,
        grace_ms: 150
    };
    if values[1] == "deadline" {
        limits.deadline_ms = 200;
    }
    var argv: const u8[:][>..] = [];
    for value in values[3..] {
        argv.push(value);
    }
    let result = process::run(argv, values[2], limits);
    if result.pid > 0 {
        assert(process_support::reaped(result.pid) == 1);
    }
    var kind: const u8[:] = "invalid";
    if result.outcome == process::Outcome.Exited {
        kind = "exit";
    }
    else if result.outcome == process::Outcome.LaunchFailed {
        kind = "launch";
    }
    else if result.outcome == process::Outcome.Signaled {
        kind = "signal";
    }
    else if result.outcome == process::Outcome.Cancelled {
        kind = "cancel";
    }
    else if result.outcome == process::Outcome.Deadline {
        kind = "deadline";
    }
    else if result.outcome == process::Outcome.SystemError {
        kind = "system";
    }
    print("RESULT ", kind, " ", result.exit_code, " ", result.signal, " ", result.native_error,
        " ", result.pid, " ", result.reaped, " ", result.cleanup_error);
}
