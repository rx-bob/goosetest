// State sentinels prove hard stops, soft continuation, and one outcome per case.
namespace execution_test;

import goosetest;

fn test_hard_stop() {
    var t = goosetest::Test {
    };
    var reached = false;
    goosetest::run_case(t) {
        hard_helper(t);
        reached = true;
    }
    assert( !reached);
    assert(t.assertions == 1);
    assert(t.failures == 1);
    assert(goosetest::case_status(t) == 1);
    goosetest::run_case(t) {
        t.assert_true(true);
        reached = true;
    }
    assert(reached);
    assert(t.failures == 0);
    assert(goosetest::case_status(t) == 0);
}

fn hard_helper(t: goosetest::Test&) {
    t.assert_eq(1, 2, "hard stop");
    t.fail("unreachable helper statement");
}

fn test_soft_failures() {
    var t = goosetest::Test {
    };
    var reached = false;
    var failed_cases = 0;
    goosetest::run_case(t) {
        t.check_eq(10, 20, "first");
        t.check_eq(30, 40, "second");
        t.check_eq(50, 50);
        reached = true;
    }
    failed_cases += goosetest::case_status(t);
    assert(reached);
    assert(t.assertions == 3);
    assert(t.failures == 2);
    assert(failed_cases == 1);
    let expected = "first: expected: <10> actual: <20>\nsecond: expected: <30> actual: <40>\n";
    assert(t.diagnostics == expected);
}

fn test_soft_then_hard() {
    var t = goosetest::Test {
    };
    goosetest::run_case(t) {
        t.check_eq(1, 2);
        t.assert_false(true);
        t.check_eq(3, 4);
    }
    assert(t.assertions == 2);
    assert(t.failures == 2);
    assert(goosetest::case_status(t) == 1);
}
