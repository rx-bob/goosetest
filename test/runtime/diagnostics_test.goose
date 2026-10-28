// Exact budgets preserve complete failures and produce a separate terminal error.
namespace diagnostics_test;

import std;

import goosetest;
import test_support.runtime;

let FAILURE_TEXT = "expected: <1> actual: <2>\n";
var format_calls: i64 = 0;
struct Value {
    number: i64
}

fn format(out: u8[>..]&, value: Value) {
    format_calls += 1;
    ::format(out, value.number);
}

fn test_failure_limit(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            failures: 2,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
            t.check_eq(1, 2);
            t.check_eq(1, 2);
        }
        assert(t.results.failures.len == 2);
        assert(!t.results.incomplete);
        assert(goosetest::run_status(t.results) == 1);
        var reached = false;
        goosetest::execute_case(t) {
            t.check_eq(3, 4);
            reached = true;
        }
        assert(!reached);
        assert(t.results.failures.len == 2);
        assert(t.results.diagnostics.len == FAILURE_TEXT.len * 2);
        assert(t.results.cases.len == 2);
        assert(t.results.cases[1].outcome == goosetest::Outcome.RunnerError);
        assert(t.results.cases[1].failure_count == 0);
        assert(t.results.totals.failed == 1);
        assert(t.results.totals.runner_errors == 1);
        assert(t.results.totals.assertions == 3);
        assert(t.results.terminal == goosetest::TerminalError.FailureLimit);
        assert(goosetest::run_status(t.results) == 2);
        assert(goosetest::diagnostic_text(t.results, t.results.failures[0].message) == FAILURE_TEXT);
    }
}

fn test_byte_limit(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: FAILURE_TEXT.len,
            ..
        }) {
        t =>
        var reached = false;
        goosetest::execute_case(t) {
            t.check_eq(1, 2);
            assert(t.results.diagnostics.len == FAILURE_TEXT.len);
            assert(!t.results.incomplete);
            t.check_eq(3, 4);
            reached = true;
        }
        assert(!reached);
        assert(t.results.diagnostics == FAILURE_TEXT);
        assert(t.results.failures.len == 1);
        assert(t.results.cases[0].failure_count == 1);
        assert(t.results.cases[0].outcome == goosetest::Outcome.RunnerError);
        assert(t.results.totals.runner_errors == 1);
        assert(t.results.totals.failed == 0);
        assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        assert(goosetest::run_status(t.results) == 2);
        assert(goosetest::terminal_diagnostic(t.results) == "incomplete run: diagnostic byte limit exhausted");
    }
}

fn test_byte_boundary(outer: goosetest::Test&) {
    let budgets: i64[2] = [FAILURE_TEXT.len, FAILURE_TEXT.len - 1];
    for budget in budgets {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            goosetest::execute_case(t) {
                t.assert_eq(1, 2);
            }
            if budget == FAILURE_TEXT.len {
                assert(goosetest::run_status(t.results) == 1);
                assert(t.results.diagnostics == FAILURE_TEXT);
                assert(t.results.failures.len == 1);
            } else {
                assert(goosetest::run_status(t.results) == 2);
                assert(t.results.diagnostics.len == 0);
                assert(t.results.failures.len == 0);
            }
        }
    }
}

fn test_zero_failure_budget(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            failures: 0,
            diagnostic_bytes: 0,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
            t.assert_eq(1, 1);
        }
        assert(goosetest::run_status(t.results) == 0);
        format_calls = 0;
        goosetest::execute_case(t) {
            t.check_eq(Value {
                    number: 1
                }, Value {
                    number: 2
                });
        }
        assert(format_calls == 0);
        assert(t.results.failures.len == 0);
        assert(t.results.diagnostics.len == 0);
        assert(t.results.terminal == goosetest::TerminalError.FailureLimit);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_phase_and_lifetime(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        record_temporary_values(t);
        goosetest::execute_case(t) {
            t.assert_true(true);
        }
        assert(t.results.failures.len == 2);
        assert(t.results.failures[0].phase == goosetest::Phase.Setup);
        assert(t.results.failures[1].phase == goosetest::Phase.Cleanup);
        let first = goosetest::diagnostic_text(t.results, t.results.failures[0].message);
        assert(first == "temporary: expected: <wanted> actual: <actual>\n");
        assert(goosetest::diagnostic_text(t.results, t.results.failures[1].message) == FAILURE_TEXT);
        assert(t.results.cases[0].first_failure == 0);
        assert(t.results.cases[0].failure_count == 2);
        assert(t.results.cases[1].first_failure == 2);
        assert(t.results.cases[1].failure_count == 0);
        assert(t.phase == goosetest::Phase.Body);
    }
}

fn test_format_budget(outer: goosetest::Test&) {
    let envelope = "expected: <> actual: <>\n";
    let budgets: i64[2] = [0, envelope.len + 1];
    for budget in budgets {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            format_calls = 0;
            goosetest::execute_case(t) {
                t.check_eq(Value {
                        number: 1
                    }, Value {
                        number: 2
                    });
            }
            if budget == 0 {
                assert(format_calls == 0);
            } else {
                assert(format_calls == 2);
            }
            assert(t.results.diagnostics.len == 0);
            assert(t.results.failures.len == 0);
            assert(t.results.cases[0].outcome == goosetest::Outcome.RunnerError);
            assert(goosetest::run_status(t.results) == 2);
            var reached = false;
            goosetest::execute_case(t) {
                reached = true;
            }
            assert(!reached);
            assert(t.results.cases.len == 1);
            assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        }
    }
}

fn test_explicit_budget(outer: goosetest::Test&) {
    let text = "label: explicit failure\n";
    let budgets: i64[2] = [text.len, text.len - 1];
    for budget in budgets {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            goosetest::execute_case(t) {
                t.fail("label");
            }
            if budget == text.len {
                assert(t.results.diagnostics == text);
                assert(goosetest::run_status(t.results) == 1);
            } else {
                assert(t.results.diagnostics.len == 0);
                assert(t.results.failures.len == 0);
                assert(goosetest::run_status(t.results) == 2);
            }
        }
    }
}

fn record_temporary_values(t: goosetest::Test&) {
    goosetest::execute_case(t) {
        var message: u8[>..] = [];
        var actual: u8[>..] = [];
        message.append("temporary");
        actual.append("actual");
        t.phase = goosetest::Phase.Setup;
        t.check_eq("wanted", actual[..], message);
        t.phase = goosetest::Phase.Cleanup;
        t.check_eq(1, 2);
    }
}
