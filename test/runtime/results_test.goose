// Outcome accounting is independent of failure count and terminal storage.
namespace results_test;

import goosetest;
import test_support.runtime;

fn test_totals(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
        }
        goosetest::execute_case(t) {
            t.check_eq(1, 2);
            t.check_eq(3, 4);
        }
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
            }, "disabled");
        goosetest::record_filtered(t.results);
        goosetest::record_filtered(t.results);
        assert(t.results.cases.len == 3);
        assert(t.results.cases[0].outcome == goosetest::Outcome.Passed);
        assert(t.results.cases[1].outcome == goosetest::Outcome.Failed);
        assert(t.results.cases[1].failure_count == 2);
        assert(t.results.cases[2].outcome == goosetest::Outcome.Skipped);
        assert(t.results.cases[2].failure_count == 0);
        assert(t.results.totals.passed == 1);
        assert(t.results.totals.failed == 1);
        assert(t.results.totals.skipped == 1);
        assert(t.results.totals.runner_errors == 0);
        assert(t.results.totals.filtered == 2);
        assert(t.results.totals.assertions == 2);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_case_limit(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            cases: 1,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
        }
        assert(goosetest::run_status(t.results) == 0);
        var reached = false;
        goosetest::execute_case(t) {
            reached = true;
        }
        assert( !reached);
        assert(t.results.incomplete);
        assert(t.results.terminal == goosetest::TerminalError.CaseLimit);
        assert(t.results.cases.len == 1);
        assert(t.results.totals.passed == 1);
        assert(t.results.totals.runner_errors == 0);
        assert(goosetest::run_status(t.results) == 2);
        assert(goosetest::case_status(t) == 2);
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
            }, "no capacity");
        assert(t.results.cases.len == 1);
        assert(goosetest::terminal_diagnostic(t.results) == "incomplete run: case record limit exhausted");
    }
}

fn test_zero_limits(outer: goosetest::Test&) {
    let limits = goosetest::Limits {
        cases: 0,
        failures: 0,
        diagnostic_bytes: 0,
        metadata_bytes: 0
    };
    runtime_support::with_test(limits) {
        t =>
        assert(goosetest::run_status(t.results) == 2);
        goosetest::execute_case(t) {
            t.fail("unreachable");
        }
        assert(t.results.cases.len == 0);
        assert(t.results.failures.len == 0);
        assert(t.results.diagnostics.len == 0);
        assert(t.results.metadata.len == 0);
        assert(t.results.terminal == goosetest::TerminalError.CaseLimit);
        assert(goosetest::terminal_diagnostic(t.results).len > 0);
    }
}

fn test_skipped_only(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            cases: 1,
            ..
        }) {
        t =>
        goosetest::record_filtered(t.results);
        assert(goosetest::run_status(t.results) == 2);
        goosetest::skip_case(t.results, goosetest::CaseIdentity {
            }, "pending");
        assert(goosetest::run_status(t.results) == 0);
        assert(t.results.totals.skipped == 1);
        assert(t.results.totals.filtered == 1);
        assert(t.results.totals.assertions == 0);
        assert(goosetest::metadata_text(t.results, t.results.cases[0].skip_reason) == "pending");
    }
}

fn test_invalid_limits(outer: goosetest::Test&) {
    let limits: goosetest::Limits[4] = [
        goosetest::Limits {
            cases: - 1,
            ..
        },
        goosetest::Limits {
            failures: - 1,
            ..
        },
        goosetest::Limits {
            diagnostic_bytes: - 1,
            ..
        },
        goosetest::Limits {
            metadata_bytes: - 1,
            ..
        },
    ];
    for limit in limits {
        runtime_support::with_test(limit) {
            t =>
            var reached = false;
            goosetest::execute_case(t) {
                reached = true;
            }
            assert( !reached);
            assert(t.results.cases.len == 0);
            assert(t.results.incomplete);
            assert(goosetest::run_status(t.results) == 2);
            assert(t.results.terminal == goosetest::TerminalError.InvalidLimits);
            assert(goosetest::terminal_diagnostic(t.results) == "incomplete run: limits must be nonnegative");
        }
    }
}

fn test_not_run_without_failure(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        goosetest::not_run_case(t.results, goosetest::CaseIdentity {
                ..
            });
        assert(t.results.totals.not_run == 1);
        assert(t.results.totals.passed == 0 && t.results.totals.skipped == 0);
        assert(goosetest::run_status(t.results) == 2);
    }
}
