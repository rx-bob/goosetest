// Exercises a hard assertion through the global bridge from a user namespace.
namespace alpha_test;

import goosetest;

fn test_hard_stop(t: goosetest::Test&) {
    t.assert_eq(1, 2);
    t.reached = true;
}
