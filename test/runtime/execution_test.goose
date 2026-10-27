// State sentinels prove hard stops, soft continuation, and one outcome per case.
namespace execution_test;

import goosetest;
import goosetest.test_support.runtime;

fn test_hard_stop() {
    runtime_support::with_test() {
        t =>
        var reached = false;
        goosetest::execute_case(t) {
            hard_helper(t);
            reached = true;
        }
        assert( !reached);
        assert(t.assertions == 1);
        assert(t.failures == 1);
        assert(goosetest::case_status(t) == 1);
        goosetest::execute_case(t) {
            t.assert_true(true);
            reached = true;
        }
        assert(reached);
        assert(t.failures == 0);
        assert(goosetest::case_status(t) == 0);
    }
}

fn hard_helper(t: goosetest::Test&) {
    t.assert_eq(1, 2, "hard stop");
    t.fail("unreachable helper statement");
}

fn test_soft_failures() {
    runtime_support::with_test() {
        t =>
        var reached = false;
        var failed_cases = 0;
        goosetest::execute_case(t) {
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
        assert(goosetest::case_diagnostics(t) == expected);
    }
}

fn test_soft_then_hard() {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.check_eq(1, 2);
            t.assert_false(true);
            t.check_eq(3, 4);
        }
        assert(t.assertions == 2);
        assert(t.failures == 2);
        assert(goosetest::case_status(t) == 1);
    }
}

fn test_phase_failures() {
    for mode in 0..5 {
        runtime_support::with_test() {
            t =>
            var events: i64[>..] = [];
            goosetest::execute_fixture(t) {
                var fixture: i64 = 0;
                let ready = goosetest::run_phase(t, goosetest::Phase.Setup) {
                    events.push(1);
                    fixture = 42;
                    if mode == 1 {
                        t.fail("setup");
                    }
                    if mode == 2 {
                        t.check_eq(0, 1, "soft setup");
                    }
                };
                if ready {
                    goosetest::run_phase(t, goosetest::Phase.Body) {
                        events.push(2);
                        t.assert_eq(42, fixture);
                        if mode == 3 || mode == 4 {
                            t.fail("body");
                        }
                        events.push(3);
                    }
                }
                goosetest::run_phase(t, goosetest::Phase.Cleanup) {
                    events.push(4);
                    t.assert_eq(42, fixture);
                    if mode == 4 {
                        t.fail("cleanup");
                    }
                    events.push(5);
                }
            }
            assert(t.phase == goosetest::Phase.Body && !t.active);
            assert(t.results.cases.len == 1);
            if mode == 0 {
                assert(events == [1, 2, 3, 4, 5]);
            }
            if mode == 1 || mode == 2 {
                assert(events == [1, 4, 5]);
            }
            if mode == 3 {
                assert(events == [1, 2, 4, 5]);
            }
            if mode == 4 {
                assert(events == [1, 2, 4]);
                assert(t.results.failures.len == 2);
                assert(t.results.failures[0].phase == goosetest::Phase.Body);
                assert(t.results.failures[1].phase == goosetest::Phase.Cleanup);
                assert(t.results.totals.failed == 1);
            }
            if mode == 1 || mode == 2 {
                assert(t.results.failures[0].phase == goosetest::Phase.Setup);
            }
            if mode == 0 {
                assert(goosetest::run_status(t.results) == 0);
            }
            else {
                assert(goosetest::run_status(t.results) == 1);
            }
        }
    }
}

fn test_cleanup_after_limit() {
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 0,
            ..
        }) {
        t =>
        var cleaned = false;
        var body = false;
        goosetest::execute_fixture(t) {
            let ready = goosetest::run_phase(t, goosetest::Phase.Setup) {
                t.fail("cannot retain this failure");
            };
            if ready {
                goosetest::run_phase(t, goosetest::Phase.Body) {
                    body = true;
                }
            }
            goosetest::run_phase(t, goosetest::Phase.Cleanup) {
                cleaned = true;
            }
        }
        assert(cleaned && !body);
        assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        assert(t.results.cases[0].outcome == goosetest::Outcome.RunnerError);
        assert(goosetest::run_status(t.results) == 2);
        var constructed = false;
        goosetest::execute_fixture(t) {
            constructed = true;
        }
        assert( !constructed);
    }
}
