// Independent sentinels verify retained outcomes before the parent checks exit status.
namespace runtime_harness;

import goosetest;

fn run_cases(t: goosetest::Test&, should_fail: bool) {
    let expected_failures = if should_fail {
        2
    } else {
        0
    };
    let expected_failed_case = if should_fail {
        1
    } else {
        0
    };
    var reached = false;
    goosetest::execute_case(t) {
        t.check_eq(false, should_fail, "first soft check");
        t.check_eq(false, should_fail, "second soft check");
        t.assert_true(true);
    }
    assert(t.failures == expected_failures);
    assert(t.results.totals.failed == expected_failed_case);
    goosetest::execute_case(t) {
        t.assert_false(should_fail, "hard check");
        reached = true;
    }
    if t.results.incomplete {
        assert(!reached);
        assert(t.results.cases.len == 1);
        assert(goosetest::run_status(t.results) == 2);
        return;
    }
    assert(reached != should_fail);
    goosetest::execute_case(t) {
        t.assert_eq("next case", "next case");
        reached = true;
    }
    assert(reached);
    assert(t.results.cases.len == 3);
    assert(t.results.totals.failed == expected_failures);
    assert(t.results.totals.assertions == 5);
}
