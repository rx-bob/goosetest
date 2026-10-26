// Expected-first assertions record diagnostics only on failure, without printing.
namespace goosetest;

import std;

import src.runtime.context;
import src.runtime.execution;

// Generic context avoids eager checking of unused non-local-return functions.
// begin_failure/assert_eq constrain the context to Test& when instantiated.
fn fail<C>(t: C&, message: u8[:]) {
    t.assertions += 1;
    begin_failure(t, message);
    t.diagnostics.append("explicit failure\n");
    return from goosetest::run_case;
}

fn assert_true<C>(t: C&, condition: bool, message: u8[:] = "") {
    assert_eq(t, true, condition, message);
}

fn assert_false<C>(t: C&, condition: bool, message: u8[:] = "") {
    assert_eq(t, false, condition, message);
}

fn assert_eq<T>(t: Test&, expected: T, actual: T, message: u8[:] = "") {
    t.assertions += 1;
    if expected != actual {
        record_equality(t, expected, actual, message);
        return from goosetest::run_case;
    }
}

fn assert_ne<T>(t: Test&, unexpected: T, actual: T, message: u8[:] = "") {
    t.assertions += 1;
    if unexpected == actual {
        begin_failure(t, message);
        format(t.diagnostics, "unexpected: <", unexpected, "> actual: <", actual, ">\n");
        return from goosetest::run_case;
    }
}

fn check_eq<T>(t: Test&, expected: T, actual: T, message: u8[:] = "") {
    t.assertions += 1;
    if expected != actual {
        record_equality(t, expected, actual, message);
    }
}

fn record_equality<T>(t: Test&, expected: T, actual: T, message: u8[:]) {
    begin_failure(t, message);
    format(t.diagnostics, "expected: <", expected, "> actual: <", actual, ">\n");
}

fn begin_failure(t: Test&, message: u8[:]) {
    t.failures += 1;
    if message.len > 0 {
        format(t.diagnostics, message, ": ");
    }
}
