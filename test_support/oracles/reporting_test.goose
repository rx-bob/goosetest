// Independent harness exercises retained runtime records without discovery or generation.

import goosetest from "../..";

import os;
import std;

import goosetest.src.reporting.console;
import goosetest.test_support.runtime;

struct Decision {
    allowed: bool,
    role: const u8[:],
    reason: const u8[:],
}

fn main() {
    assert(arg_count() == 2);
    var mode: u8[>..] = [];
    arg(1, mode);
    var status: i32 = 2;
    runtime_support::with_test() {
        t =>
        if mode == "passing" || mode == "failing" {
            reference_cases(t, mode == "failing");
            reporting::report(t.results, 6);
        } else if mode == "mixed" {
            mixed_cases(t);
            reporting::report(t.results, 6);
        } else if mode == "incomplete" {
            goosetest::execute_case(t, identity("test_before", 8)) {
                t.assert_true(true);
            }
            goosetest::stop_run(t.results, goosetest::TerminalError.DiagnosticLimit);
            reporting::report(t.results, 4);
        } else {
            assert(false);
        }
        status = goosetest::run_status(t.results);
    }
    exit(status);
}

fn identity(name: u8[:], line: i64, display: u8[:] = "") -> goosetest::CaseIdentity {
    return goosetest::CaseIdentity {
        test_path: "test/permissions_test.goose",
        namespace_name: "permissions_test",
        function_name: name,
        display_name: display,
        declaration_line: line,
    };
}

fn reference_cases(t: goosetest::Test&, negative: bool) {
    var reason: const u8[:] = "insufficient_role";
    if negative {
        reason = "ok";
    }
    goosetest::execute_case(t, identity("test_viewer", 30, "viewer write access")) {
        let expected = Decision {
            allowed: negative,
            role: "viewer",
            reason: reason,
        };
        let actual = Decision {
            allowed: false,
            role: "viewer",
            reason: "insufficient_role",
        };
        t.assert_struct_eq(expected, actual, "viewer write check");
    }
    for index in 0..4 {
        let name = str("test_valid_", index);
        goosetest::execute_case(t, identity(name, 40 + index)) {
            t.assert_true(true);
        }
    }
    goosetest::skip_case(t.results, identity("test_pending", 60, "clock skew"), "pending clock support");
}

fn mixed_cases(t: goosetest::Test&) {
    goosetest::execute_case(t, identity("test_phases", 10, "label\n\x1B\t\\")) {
        t.phase = goosetest::Phase.Setup;
        t.check_eq(1, 2, "setup\nmessage");
        t.phase = goosetest::Phase.Body;
        t.check_eq(3, 4, "body\x1Bmessage");
        t.phase = goosetest::Phase.Cleanup;
        t.check_eq(5, 6, "cleanup\rmessage");
    }
    goosetest::execute_case(t, identity("test_suite_hooks", 20)) {
        t.phase = goosetest::Phase.SuiteSetup;
        t.check_eq(7, 8, "suite setup");
        t.phase = goosetest::Phase.SuiteCleanup;
        t.check_eq(9, 10, "suite cleanup");
    }
    goosetest::execute_case(t, identity("test_pass", 30)) {
        t.assert_true(true);
    }
    goosetest::skip_case(t.results, identity("test_skip", 40), "pending\nreason\x1B");
    goosetest::record_filtered(t.results);
    goosetest::record_filtered(t.results);
}
