// The public bridge recovers failures from a separate consumer module.
namespace runtime_integration_test;

import goosetest;
import test_support.runtime;
import test_support.runtime_harness;

fn test_public_boundary(outer: goosetest::Test&) {
    var observed_failure = false;
    runtime_support::with_test() {
        inner =>
        runtime_harness::run_cases(inner, true);
        observed_failure = goosetest::run_status(inner.results) == 1;
    }
    outer.assert_true(observed_failure);
}

fn test_public_success(outer: goosetest::Test&) {
    var observed_success = false;
    runtime_support::with_test() {
        inner =>
        runtime_harness::run_cases(inner, false);
        observed_success = goosetest::run_status(inner.results) == 0;
    }
    outer.assert_true(observed_success);
}
