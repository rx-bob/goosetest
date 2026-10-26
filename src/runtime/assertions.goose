// Expected-first assertions record diagnostics only on failure, without printing.
namespace goosetest;

import src.runtime.context;
import src.runtime.diagnostics;
import src.runtime.execution;

// Generic context avoids eager checking of unused non-local-return functions.
// Diagnostic helpers constrain the context to Test& when instantiated.
fn fail<C>(t: C&, message: u8[:]) {
    t.assertions += 1;
    record_explicit(t, message);
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
        record_inequality(t, unexpected, actual, message);
        return from goosetest::run_case;
    }
}

fn check_eq<T>(t: Test&, expected: T, actual: T, message: u8[:] = "") {
    t.assertions += 1;
    if expected != actual {
        if !record_equality(t, expected, actual, message) {
            return from goosetest::run_case;
        }
    }
}
