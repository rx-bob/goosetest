// Public package facade and deliberate global vocabulary for assertion UFCS.
// Execution helpers and Test remain in the goosetest namespace.
// C defers unused hard assertions; typed implementation helpers still require Test&.
// Intentionally expose qualified reporting alongside the assertion runtime.

import src.reporting.console;
import src.runtime.assertions;
import src.runtime.assertions_struct;
import src.runtime.assertions_values;
import src.runtime.context;
import src.runtime.execution;
import src.runtime.results;

fn fail<C>(t: C&, message: u8[:]) {
    goosetest::fail(t, message);
}

fn assert_true<C>(t: C&, condition: bool, message: u8[:] = "") {
    goosetest::assert_true(t, condition, message);
}

fn assert_false<C>(t: C&, condition: bool, message: u8[:] = "") {
    goosetest::assert_false(t, condition, message);
}

fn assert_eq<T>(t: goosetest::Test&, expected: T, actual: T, message: u8[:] = "") {
    goosetest::assert_eq(t, expected, actual, message);
}

fn assert_ne<T>(t: goosetest::Test&, unexpected: T, actual: T, message: u8[:] = "") {
    goosetest::assert_ne(t, unexpected, actual, message);
}

fn check_eq<T>(t: goosetest::Test&, expected: T, actual: T, message: u8[:] = "") {
    goosetest::check_eq(t, expected, actual, message);
}

fn assert_contains<C>(t: C&, expected_fragment: u8[:], actual_text: u8[:], message: u8[:] = "") {
    goosetest::assert_contains(t, expected_fragment, actual_text, message);
}

fn assert_near<C>(t: C&, expected: f64, actual: f64, absolute_tolerance: f64, message: u8[:] = "") {
    goosetest::assert_near(t, expected, actual, absolute_tolerance, message);
}

fn assert_struct_eq<T>(t: goosetest::Test&, expected: const T&, actual: const T&, message: u8[:] = "") {
    goosetest::assert_struct_eq(t, expected, actual, message);
}
