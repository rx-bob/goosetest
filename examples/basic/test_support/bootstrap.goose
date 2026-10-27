// Independent explicit runtime oracle retained alongside generated orchestration.
namespace basic_bootstrap;

import goosetest;

import os;
import std;

import test.calculator_test;

fn run() -> i32 {
    var cases: goosetest::CaseResult[>..] = [];
    var failures: goosetest::Failure[>..] = [];
    var diagnostics: u8[>..] = [];
    var metadata: u8[>..] = [];
    var results = goosetest::new_results(cases, failures, diagnostics, metadata);
    var t = goosetest::Test {
        results: results,
        ..
    };
    run_cases(t);
    report(results);
    return goosetest::run_status(results);
}

fn run_cases(t: goosetest::Test&) {
    goosetest::execute_case(t, identity("test_addition")) {
        calculator_test::test_addition(t);
    }
    goosetest::execute_case(t, identity("test_subtraction")) {
        calculator_test::test_subtraction(t);
    }
    goosetest::execute_case(t, identity("test_zero_identity")) {
        calculator_test::test_zero_identity(t);
    }
}

fn identity(function_name: u8[:]) -> goosetest::CaseIdentity {
    return goosetest::CaseIdentity {
        test_path: "test/calculator_test.goose",
        namespace_name: "calculator_test",
        function_name: function_name,
        ..
    };
}

fn report(results: goosetest::Results&) {
    // The case table is bounded by the runtime's configured case-record limit.
    for result in results.cases {
        print(outcome_label(result.outcome), " ", goosetest::metadata_text(results, result.identity.function_name));
        write_stdout(goosetest::diagnostic_text(results, result.diagnostics));
    }
    if results.incomplete {
        print(goosetest::terminal_diagnostic(results));
    }
    print("Cases: ", results.totals.passed, " passed, ", results.totals.failed, " failed, ",
        results.totals.skipped, " skipped, ", results.totals.runner_errors, " errors");
}

fn outcome_label(outcome: goosetest::Outcome) -> const u8[:] {
    match outcome {
        Passed => {
            return "PASS";
        },
        Failed => {
            return "FAIL";
        },
        Skipped => {
            return "SKIP";
        },
        NotRun => {
            return "NOT RUN";
        },
        RunnerError => {
            return "ERROR";
        },
    }
}
