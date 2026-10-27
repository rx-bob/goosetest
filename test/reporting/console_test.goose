// Console output is a deterministic projection of finalized retained records.
namespace console_test;

import goosetest;
import goosetest.src.reporting.console;
import goosetest.test_support.runtime;

import std;

fn test_case_order_and_totals() {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t, identity("test_z", 20)) {
            t.check_eq(1, 2, "one\nmessage");
            t.check_eq(3, 4);
        }
        goosetest::execute_case(t, identity("test_a", 10)) {
            t.assert_true(true);
        }
        goosetest::skip_case(t.results, identity("test_skip", 30), "pending\x1B");
        var before: u8[>..] = [];
        reporting::render(t.results, 4) {
            chunk => before.append(chunk);
        }
        let first = t.results.cases[0];
        t.results.cases[0] = t.results.cases[2];
        t.results.cases[2] = first;
        var after: u8[>..] = [];
        reporting::render(t.results, 4) {
            chunk => after.append(chunk);
        }
        assert(before == after);
        assert(find(before[..], "Cases: 1 passed, 1 failed, 1 skipped, 0 errors, 1 not run") >= 0);
        assert(find(before[..], "one\\x0Amessage") >= 0);
        assert(find(before[..], "pending\\x1B") >= 0);
        assert(find(before[..], "PASS test/a_test.goose::a_test::test_a")
            < find(before[..], "FAIL test/a_test.goose::a_test::test_z"));
        assert(t.results.failures.len == 2);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_active_and_incomplete() {
    runtime_support::with_test() {
        t =>
        var active: u8[>..] = [];
        goosetest::execute_case(t, identity("test_active", 9)) {
            reporting::render(t.results, 2) {
                chunk => active.append(chunk);
            }
            t.assert_true(true);
        }
        assert(find(active[..], "PASS ") < 0);
        assert(find(active[..], "incomplete") >= 0);
        goosetest::stop_run(t.results, goosetest::TerminalError.CaseLimit);
        var incomplete: u8[>..] = [];
        reporting::render(t.results, 3) {
            chunk => incomplete.append(chunk);
        }
        assert(find(incomplete[..], "incomplete") >= 0);
        assert(find(incomplete[..], "2 not run") >= 0);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn identity(name: u8[:], line: i64) -> goosetest::CaseIdentity {
    return goosetest::CaseIdentity {
        test_path: "test/a_test.goose",
        namespace_name: "a_test",
        function_name: name,
        display_name: "display\nlabel",
        declaration_line: line,
    };
}

fn test_runner_error_record() {
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 0,
            ..
        }) {
        t =>
        goosetest::execute_case(t, identity("test_limit", 19)) {
            t.assert_eq(1, 2);
        }
        var text: u8[>..] = [];
        reporting::render(t.results, 3) {
            chunk => text.append(chunk);
        }
        assert(find(text[..], "Cases: 0 passed, 0 failed, 0 skipped, 1 errors, 2 not run") >= 0);
        assert(find(text[..], "ERROR test/a_test.goose::a_test::test_limit") >= 0);
        assert(find(text[..], "incomplete run: diagnostic byte limit exhausted") >= 0);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_reused_id_order() {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t, identity("test_same", 10)) {
            t.assert_eq(1, 2);
        }
        goosetest::execute_case(t, identity("test_same", 10)) {
            t.assert_true(true);
        }
        var first: u8[>..] = [];
        reporting::render(t.results) {
            chunk => first.append(chunk);
        }
        let record = t.results.cases[0];
        t.results.cases[0] = t.results.cases[1];
        t.results.cases[1] = record;
        t.results.totals.passed = 999;
        var second: u8[>..] = [];
        reporting::render(t.results) {
            chunk => second.append(chunk);
        }
        assert(first == second);
        assert(find(second[..], "Cases: 1 passed, 1 failed") >= 0);
    }
}
