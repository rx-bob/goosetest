// Hand-written public-package harness; the parent checks actual process status.
import goosetest from "..";

import os;

fn main() {
    var option: u8[>..] = [];
    if arg_count() == 2 {
        arg(1, option);
    }
    if arg_count() > 2 || (option.len > 0 && option != "--fail") {
        exit(2);
    }
    let should_fail = option == "--fail";
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
    var t = goosetest::Test {
    };
    var failed_cases = 0;
    var reached = false;

    goosetest::run_case(t) {
        t.check_eq(false, should_fail, "first soft check");
        t.check_eq(false, should_fail, "second soft check");
        t.assert_true(true);
    }
    failed_cases += goosetest::case_status(t);
    assert(t.failures == expected_failures);
    assert(failed_cases == expected_failed_case);

    goosetest::run_case(t) {
        t.assert_false(should_fail, "hard check");
        reached = true;
    }
    failed_cases += goosetest::case_status(t);
    assert(reached != should_fail);

    goosetest::run_case(t) {
        t.assert_eq("next case", "next case");
        reached = true;
    }
    failed_cases += goosetest::case_status(t);
    assert(reached);
    assert(failed_cases == expected_failures);
    exit(if failed_cases > 0 {
            1
        } else {
            0
        });
}
