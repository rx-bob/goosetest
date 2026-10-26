// Independent checks for per-case reset and sticky failure state.
namespace context_test;

import goosetest;
import goosetest.test_support.runtime;

fn test_reset() {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.check_eq(1, 2, "old case");
            t.assert_eq(3, 3);
        }
        assert(t.assertions == 2);
        assert(t.failures == 1);
        assert(goosetest::case_status(t) == 1);
        assert(goosetest::case_diagnostics(t).len > 0);
        goosetest::execute_case(t) {
        }
        assert(t.assertions == 0);
        assert(t.failures == 0);
        assert(goosetest::case_diagnostics(t).len == 0);
        assert(goosetest::case_status(t) == 0);
    }
}
