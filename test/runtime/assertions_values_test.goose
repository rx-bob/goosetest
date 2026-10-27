// Value assertion contracts are checked through independent structured-result assertions.
namespace assertions_values_test;

import goosetest;
import test_support.runtime;

import math;
import std;

fn test_contains_values(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.assert_contains("", "");
            t.assert_contains("", "goose");
            t.assert_contains("goose", "goose");
            t.assert_contains("goo", "goose");
            t.assert_contains("ose", "goose");
            t.assert_contains("oo", "goose");
            t.assert_contains("\0b", "a\0b");
            t.assert_contains("é", "café");
        }
        assert(t.assertions == 8);
        assert(goosetest::run_status(t.results) == 0);
        assert(t.results.diagnostics.len == 0);
    }
}

fn test_contains_failure(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        var reached = false;
        goosetest::execute_case(t) {
            t.assert_contains("long", "lo", "fragment");
            reached = true;
        }
        assert( !reached);
        assert(t.assertions == 1 && t.failures == 1);
        assert(goosetest::case_diagnostics(t) == "fragment: expected fragment: <long> actual: <lo>\n");
        assert(t.results.cases[0].outcome == goosetest::Outcome.Failed);
        goosetest::execute_case(t) {
            t.assert_contains("ok", "next ok");
        }
        assert(t.results.totals.failed == 1 && t.results.totals.passed == 1);
        goosetest::execute_case(t) {
            t.assert_contains("GO", "goose");
        }
        assert(goosetest::case_diagnostics(t) == "expected fragment: <GO> actual: <goose>\n");
        goosetest::execute_case(t) {
            t.assert_contains("a\0c", "a\0b");
        }
        assert(t.results.totals.failed == 3 && t.results.totals.passed == 1);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_near_values(outer: goosetest::Test&) {
    let infinity = exp(1000.0);
    assert(is_inf(infinity));
    let single: f32 = 1.5;
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.assert_near(single, single, 0.0);
            t.assert_near(1.0, 1.0, 0.0);
            t.assert_near(1.0, 1.25, 0.25);
            t.assert_near(1.25, 1.0, 0.25);
            t.assert_near( - 1.0, - 1.125, 0.25);
            t.assert_near( - 0.0, 0.0, - 0.0);
            t.assert_near(infinity, infinity, 0.0);
            t.assert_near( - infinity, - infinity, 1.0);
        }
        assert(t.assertions == 8);
        assert(goosetest::run_status(t.results) == 0);
        assert(t.results.diagnostics.len == 0);
    }
}

fn test_near_failures(outer: goosetest::Test&) {
    let infinity = exp(1000.0);
    let nan = sqrt( - 1.0);
    assert(is_inf(infinity) && is_nan(nan));
    near_failure(1.0, 1.25, 0.125, false);
    near_failure(1.0, 1.25, 0.0, false);
    near_failure(1.0, 1.0, - 0.1, true);
    near_failure(1.0, 1.0, infinity, true);
    near_failure(1.0, 1.0, - infinity, true);
    near_failure(1.0, 1.0, nan, true);
    near_failure(infinity, infinity, infinity, true);
    near_failure(nan, nan, 0.0, false);
    near_failure(nan, 1.0, 1.0, false);
    near_failure(1.0, nan, 1.0, false);
    near_failure(infinity, - infinity, 1.0, false);
    near_failure(infinity, 1.0, 1.0, false);
    near_failure(1.0, infinity, 1.0, false);
    near_failure(1e308, - 1e308, 1e308, false);
}

fn near_failure(expected: f64, actual: f64, tolerance: f64, invalid: bool) {
    runtime_support::with_test() {
        t =>
        var reached = false;
        goosetest::execute_case(t) {
            t.assert_near(expected, actual, tolerance, "near contract");
            reached = true;
        }
        assert( !reached);
        assert(t.assertions == 1 && t.failures == 1);
        assert(t.results.cases[0].outcome == goosetest::Outcome.Failed);
        let text = goosetest::case_diagnostics(t);
        assert(find(text, "near contract: expected: <") == 0);
        assert(find(text, "> actual: <") >= 0);
        assert(find(text, "> absolute tolerance: <") >= 0);
        assert((find(text, "tolerance must be finite and nonnegative") >= 0) == invalid);
        goosetest::execute_case(t) {
            t.assert_near(2.0, 2.0, 0.0);
        }
        assert(t.results.totals.failed == 1 && t.results.totals.passed == 1);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_value_diagnostic_budgets(outer: goosetest::Test&) {
    let message = "expected fragment: <missing> actual: <text>\n";
    let budgets: i64[2] = [message.len, message.len - 1];
    for budget in budgets {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            goosetest::execute_case(t) {
                t.assert_contains("missing", "text");
            }
            if budget == message.len {
                assert(goosetest::run_status(t.results) == 1);
                assert(t.results.diagnostics == message);
            } else {
                assert(goosetest::run_status(t.results) == 2);
                assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
                assert(t.results.diagnostics.len == 0);
            }
        }
    }
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 0,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
            t.assert_near(1.0, 1.0, 0.0);
            t.assert_contains("", "text");
        }
        assert(goosetest::run_status(t.results) == 0);
        goosetest::execute_case(t) {
            t.assert_near(1.0, 2.0, 0.0);
        }
        assert(goosetest::run_status(t.results) == 2);
        assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        assert(t.results.diagnostics.len == 0);
    }
}
