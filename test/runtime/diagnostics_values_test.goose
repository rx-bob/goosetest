// Value diagnostics commit whole records at exact bounds, including invalid-tolerance reasons.
namespace diagnostics_values_test;

import std;

import goosetest;
import test_support.runtime;

fn test_contains_message_boundary(outer: goosetest::Test&) {
    let expected = "label: expected fragment: <a\0b> actual: <a\0c>\n";
    for budget in[expected.len - 1, expected.len] {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            goosetest::execute_case(t) {
                t.assert_contains("a\0b", "a\0c", "label");
            }
            if budget == expected.len {
                assert(t.results.diagnostics == expected);
                assert(t.results.failures.len == 1);
                assert(goosetest::run_status(t.results) == 1);
            } else {
                assert(t.results.diagnostics.len == 0);
                assert(t.results.failures.len == 0);
                assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
            }
        }
    }
}

fn test_invalid_tolerance_boundary(outer: goosetest::Test&) {
    let expected = str("near: expected: <1.0> actual: <1.0> absolute tolerance: <-1.0>\n",
        "tolerance must be finite and nonnegative\n");
    for budget in[expected.len - 1, expected.len] {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            goosetest::execute_case(t) {
                t.assert_near(1.0, 1.0, -1.0, "near");
            }
            if budget == expected.len {
                assert(t.results.diagnostics == expected);
                assert(t.results.failures.len == 1);
                assert(goosetest::run_status(t.results) == 1);
            } else {
                assert(t.results.diagnostics.len == 0);
                assert(t.results.failures.len == 0);
                assert(goosetest::run_status(t.results) == 2);
            }
        }
    }
}
