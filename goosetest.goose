// Public package facade and deliberate global vocabulary for assertion UFCS.
// Execution helpers and Test remain in the goosetest namespace.
// C defers unused hard assertions; typed implementation helpers still require Test&.
import src.runtime.assertions;
import src.runtime.context;
import src.runtime.execution;

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
