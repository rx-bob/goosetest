// Process results distinguish real exits from launch, signal and resource failures.
namespace process_test;

import goosetest;
import test_support.selfhost;

import src.platform.process;
import test_support.process;

fn test_exits(outer: goosetest::Test&) {
    let child = selfhost_support::child();
    let cwd = selfhost_support::scratch(outer);
    assert(process_support::begin() == 1);
    for code in["0", "7", "127"] {
        let argv: const u8[:][3] = [child, "exit", code];
        let result = process::run(argv, cwd);
        assert(result.outcome == process::Outcome.Exited);
        assert(result.exit_code == (if code == "0" {
                0
            } else if code == "7" {
                7
            } else {
                127
            }));
        assert(result.reaped && result.pid > 0);
        assert(result.native_error == 0 && result.cleanup_error == 0);
        assert(process_support::reaped(result.pid) == 1);
    }
    assert(process_support::end() == 1);
}

fn test_launch_and_signal(outer: goosetest::Test&) {
    let child = selfhost_support::child();
    let cwd = selfhost_support::scratch(outer);
    assert(process_support::begin() == 1);
    let missing = process::run(["/definitely/missing/goosetest-child"], cwd);
    assert(missing.outcome == process::Outcome.LaunchFailed && missing.native_error > 0);
    assert(missing.pid == 0 && !missing.reaped);
    let argv: const u8[:][3] = [child, "exit", "0"];
    let directory = process::run(argv, "/definitely/missing/goosetest-cwd");
    assert(directory.outcome == process::Outcome.LaunchFailed && directory.native_error > 0);
    let signal_argv: const u8[:][2] = [child, "signal"];
    let signaled = process::run(signal_argv, cwd);
    assert(signaled.outcome == process::Outcome.Signaled && signaled.signal > 0);
    assert(signaled.exit_code == - 1 && signaled.reaped);
    assert(process_support::reaped(signaled.pid) == 1);
    assert(process_support::end() == 1);
}

fn test_invalid(outer: goosetest::Test&) {
    assert(process::run([], ".").outcome == process::Outcome.InvalidInput);
    assert(process::run([""], ".").outcome == process::Outcome.InvalidInput);
    assert(process::run(["x\0y"], ".").outcome == process::Outcome.InvalidInput);
    assert(process::run(["x"], "a\0b").outcome == process::Outcome.InvalidInput);
    assert(process::run(["x"], "").outcome == process::Outcome.InvalidInput);
    assert(process::run(["x"], ".", process::Limits {
            deadline_ms: 0,
            ..
        }).outcome
        == process::Outcome.InvalidInput);
    assert(process::run(["x"], ".", process::Limits {
            grace_ms: - 1,
            ..
        }).outcome
        == process::Outcome.InvalidInput);
}

fn test_bounds(outer: goosetest::Test&) {
    let child = selfhost_support::child();
    let cwd = selfhost_support::scratch(outer);
    var argv: const u8[:][>..] = [];
    argv.push(child);
    argv.push("ok");
    for index in 0..254 {
        argv.push("");
    }
    let exact_count = process::run(argv, cwd);
    assert(exact_count.outcome == process::Outcome.Exited && exact_count.exit_code == 0);
    argv.push("");
    assert(process::run(argv, cwd).outcome == process::Outcome.InvalidInput);
    var text: u8[>..] = [];
    for index in 0..65531 - child.len {
        text.push('x');
    }
    let exact_argv: const u8[:][3] = [child, "ok", text];
    let exact_bytes = process::run(exact_argv, cwd);
    assert(exact_bytes.outcome == process::Outcome.Exited && exact_bytes.exit_code == 0);
    text.push('x');
    let too_large: const u8[:][3] = [child, "ok", text];
    assert(process::run(too_large, cwd).outcome == process::Outcome.InvalidInput);
    assert(process::run(["x"], ".", process::Limits {
            deadline_ms: 86400001,
            ..
        }).outcome
        == process::Outcome.InvalidInput);
    assert(process::run(["x"], ".", process::Limits {
            grace_ms: 60001,
            ..
        }).outcome
        == process::Outcome.InvalidInput);
}
