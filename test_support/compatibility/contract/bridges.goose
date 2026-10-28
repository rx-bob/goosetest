// Deliberate global assertion vocabulary for the pinned UFCS lookup rules.

import goosetest;

fn assert_eq<T>(t: goosetest::Test&, expected: T, actual: T, message: u8[:] = "") {
    goosetest::assert_eq(t, expected, actual, message);
}
