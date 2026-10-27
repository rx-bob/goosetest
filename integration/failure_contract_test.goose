// Phase recovery, result retention and rendering must agree on incomplete runs.
namespace failure_contract_integration_test;

import goosetest;
import src.reporting.console;
import test_support.runtime;

import std;

fn test_resource_failure_still_cleans_up(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 0,
            ..
        }) {
        t =>
        var cleaned = false;
        var continued = false;
        goosetest::execute_fixture(t) {
            goosetest::run_phase(t, goosetest::Phase.Body) {
                t.assert_eq(1, 2);
                continued = true;
            }
            goosetest::run_phase(t, goosetest::Phase.Cleanup) {
                cleaned = true;
            }
        }
        assert(cleaned && !continued);
        assert(t.results.cases.len == 1);
        assert(t.results.cases[0].outcome == goosetest::Outcome.RunnerError);
        assert(t.results.failures.len == 0);
        assert(goosetest::run_status(t.results) == 2);
        var text: u8[>..] = [];
        reporting::render(t.results, 2) {
            chunk => text.append(chunk);
        }
        assert(find(text[..], "0 passed, 0 failed, 0 skipped, 1 errors, 1 not run") >= 0);
        assert(find(text[..], "diagnostic byte limit exhausted") >= 0);
    }
}

fn test_suite_failure_does_not_rewrite_pass(outer: goosetest::Test&) {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.assert_true(true);
        }
        goosetest::run_suite_hook(t, goosetest::CaseIdentity {
            }, goosetest::Phase.SuiteCleanup) {
            t.assert_eq(1, 2, "cleanup failed");
        }
        assert(t.results.cases.len == 1);
        assert(t.results.cases[0].outcome == goosetest::Outcome.Passed);
        assert(goosetest::run_status(t.results) == 1);
        var text: u8[>..] = [];
        reporting::render(t.results) {
            chunk => text.append(chunk);
        }
        assert(find(text[..], "Cases: 1 passed, 0 failed") >= 0);
        assert(find(text[..], "suite-hook errors: 1") >= 0);
        assert(find(text[..], "cleanup failed") >= 0);
    }
}
