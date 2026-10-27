// State sentinels prove hard stops, soft continuation, and one outcome per case.
namespace execution_test;

import goosetest;
import test_support.runtime;

fn test_hard_stop(outer: goosetest::Test&) {
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

fn test_soft_failures(outer: goosetest::Test&) {
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

fn test_soft_then_hard(outer: goosetest::Test&) {
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

fn test_phase_failures(outer: goosetest::Test&) {
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

fn test_cleanup_after_limit(outer: goosetest::Test&) {
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

fn suite_identity(name: u8[:], line: i64) -> goosetest::CaseIdentity {
    return goosetest::CaseIdentity {
        test_path: "test/suite_test.goose",
        namespace_name: "suite_test",
        function_name: name,
        declaration_line: line,
        ..
    };
}

fn test_suite_failures_are_separate(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        t.suite_active = true;
        let ready = goosetest::run_suite_hook(t, suite_identity("before_all", 12), goosetest::Phase.SuiteSetup) {
            assert(t.results.active_suite && t.results.active);
            t.check_eq(1, 2, "first setup cause");
            t.fail("second setup cause");
        };
        assert( !ready && !t.active && !t.results.active_suite);
        assert(t.results.cases.len == 0 && t.results.failures.len == 2);
        assert(t.results.totals.suite_failures == 1);
        assert(t.results.totals.suite_assertions == 2);
        assert(t.results.failures[0].is_suite && t.results.failures[1].is_suite);
        assert(t.results.failures[0].phase == goosetest::Phase.SuiteSetup);
        let id = t.results.failures[0].identity;
        assert(goosetest::metadata_text(t.results, id.function_name) == "before_all");
        assert(id.declaration_line == 12);
        goosetest::skip_case(t.results, suite_identity("test_skipped", 30), "suite setup failed");
        let cleaned = goosetest::run_suite_hook(t, suite_identity("after_all", 20), goosetest::Phase.SuiteCleanup) {
            t.fail("cleanup cause");
        };
        assert( !cleaned);
        assert(t.results.totals.suite_failures == 2);
        assert(t.results.totals.failed == 0 && t.results.totals.skipped == 1);
        assert(t.results.failures[2].phase == goosetest::Phase.SuiteCleanup);
        assert(t.suite_active && t.phase == goosetest::Phase.Body);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_suite_cleanup_and_next_suite(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        let ready = goosetest::run_suite_hook(t, suite_identity("before_all", 12), goosetest::Phase.SuiteSetup) {
            t.assert_true(true);
        };
        assert(ready);
        goosetest::execute_case(t) {
            t.assert_true(true);
        }
        let cleaned = goosetest::run_suite_hook(t, suite_identity("after_all", 20), goosetest::Phase.SuiteCleanup) {
            t.fail("after all failure");
        };
        assert( !cleaned);
        let next = goosetest::run_suite_hook(t, suite_identity("next_before_all", 40), goosetest::Phase.SuiteSetup) {
            t.assert_true(true);
        };
        assert(next);
        goosetest::execute_case(t) {
            t.assert_true(true);
        }
        assert(t.failures == 0 && !t.suite_hook);
        assert(t.results.cases.len == 2);
        assert(t.results.totals.passed == 2 && t.results.totals.failed == 0);
        assert(t.results.totals.suite_failures == 1 && t.results.totals.suite_assertions == 3);
        assert(t.results.totals.assertions == 5);
        assert(goosetest::run_status(t.results) == 1);
        assert(t.results.cases[0].failure_count == 0 && t.results.cases[1].failure_count == 0);
        assert(t.results.failures.len == 1 && t.results.failures[0].is_suite);
    }
}

fn test_suite_empty_selection(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        var called = false;
        let setup = goosetest::run_suite_hook(t, suite_identity("before_all", 12), goosetest::Phase.SuiteSetup, false) {
            called = true;
        };
        let cleanup = goosetest::run_suite_hook(t, suite_identity("after_all", 20),
            goosetest::Phase.SuiteCleanup, false) {
            called = true;
        };
        assert(setup && cleanup && !called);
        assert(t.results.metadata.len == 0 && t.results.failures.len == 0 && t.results.cases.len == 0);
        goosetest::skip_case(t.results, suite_identity("test_disabled", 30), "disabled");
        assert(goosetest::run_status(t.results) == 0);
        assert(t.results.totals.suite_assertions == 0 && t.results.totals.suite_failures == 0);
    }
}

fn test_suite_limit_cleanup(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            metadata_bytes: 0,
            ..
        }) {
        t =>
        var setup_called = false;
        var cleanup_called = false;
        let setup = goosetest::run_suite_hook(t, suite_identity("before_all", 12), goosetest::Phase.SuiteSetup) {
            setup_called = true;
        };
        let cleanup = goosetest::run_suite_hook(t, suite_identity("after_all", 20), goosetest::Phase.SuiteCleanup) {
            cleanup_called = true;
        };
        assert( !setup && !cleanup && !setup_called && cleanup_called);
        assert(t.results.terminal == goosetest::TerminalError.MetadataLimit);
        assert(t.results.cases.len == 0 && t.results.failures.len == 0);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_fail_fast_finalization(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        t.results.fail_fast = true;
        var cleaned = false;
        goosetest::execute_fixture(t) {
            goosetest::run_phase(t, goosetest::Phase.Body) {
                t.fail("body");
            }
            assert( !t.results.fail_fast_stop);
            goosetest::run_phase(t, goosetest::Phase.Cleanup) {
                cleaned = true;
                t.check_eq(1, 2, "cleanup");
            }
        }
        assert(cleaned && t.results.fail_fast_stop);
        goosetest::not_run_case(t.results, suite_identity("test_later", 30));
        assert(t.results.totals.not_run == 1 && t.results.totals.skipped == 0);
        assert(t.results.totals.failed == 1 && t.results.failures.len == 2);
        assert(t.results.cases[1].outcome == goosetest::Outcome.NotRun);
        assert(goosetest::run_status(t.results) == 1);
        goosetest::run_suite_hook(t, suite_identity("after_all", 40), goosetest::Phase.SuiteCleanup) {
            t.assert_true(true);
        }
        assert(t.results.fail_fast_stop && goosetest::run_status(t.results) == 1);
    }
}
