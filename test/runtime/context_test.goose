// Independent checks for per-case reset and sticky failure state.
namespace context_test;

import goosetest;

fn test_reset() {
    var t = goosetest::Test {
    };
    goosetest::run_case(t) {
        t.check_eq(1, 2, "old case");
        t.assert_eq(3, 3);
    }
    assert(t.assertions == 2);
    assert(t.failures == 1);
    assert(goosetest::case_status(t) == 1);
    assert(t.diagnostics.len > 0);
    goosetest::run_case(t) {
    }
    assert(t.assertions == 0);
    assert(t.failures == 0);
    assert(t.diagnostics.len == 0);
    assert(goosetest::case_status(t) == 0);
}
