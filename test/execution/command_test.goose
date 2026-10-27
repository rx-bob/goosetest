// Stage policy distinguishes assertion failures from incomplete process outcomes.
namespace command_test;

import goosetest.src.execution.command;
import goosetest.src.platform.process;

fn test_normal_status() {
    var result = process::ProcessResult {
        outcome: process::Outcome.Exited,
        exit_code: 0,
        pid: 42,
        reaped: true,
        ..
    };
    assert(command::stage_status(result, false) == 0);
    assert(command::stage_status(result, true) == 0);
    result.exit_code = 1;
    assert(command::stage_status(result, false) == 2);
    assert(command::stage_status(result, true) == 1);
    for code in[2, 7, 127, 255] {
        result.exit_code = code;
        assert(command::stage_status(result, false) == 2);
        assert(command::stage_status(result, true) == 2);
    }
}

fn test_incomplete_outcomes() {
    for outcome in[process::Outcome.LaunchFailed, process::Outcome.Signaled, process::Outcome.Deadline,
        process::Outcome.SystemError, process::Outcome.InvalidInput] {
        let result = process::ProcessResult {
            outcome: outcome,
            exit_code: 0,
            ..
        };
        assert(command::stage_status(result, false) == 2);
        assert(command::stage_status(result, true) == 2);
    }
}

fn test_cleanup_errors() {
    var result = process::ProcessResult {
        outcome: process::Outcome.Exited,
        exit_code: 0,
        pid: 42,
        reaped: true,
        cleanup_error: 5,
        ..
    };
    assert(command::stage_status(result, true) == 2);
    result.cleanup_error = 0;
    result.reaped = false;
    assert(command::stage_status(result, true) == 2);
}

fn test_cancellation() {
    for signal in[2, 15] {
        let result = process::ProcessResult {
            outcome: process::Outcome.Cancelled,
            signal: signal,
            exit_code: 0,
            pid: 42,
            reaped: true,
            ..
        };
        assert(command::stage_status(result, false) == 128 + signal);
        assert(command::stage_status(result, true) == 128 + signal);
    }
}
