// Hand-written consumer owns result storage through reporting and process exit.

import goosetest from "../..";

import os;

import goosetest.test_support.runtime_harness;

fn main() {
    var option: u8[>..] = [];
    if arg_count() == 2 {
        arg(1, option);
    }
    if arg_count() > 2 || (option.len > 0 && option != "--fail" && option != "--limit") {
        exit(2);
    }
    var limits = goosetest::Limits {
    };
    if option == "--limit" {
        limits.cases = 1;
    }
    var cases: goosetest::CaseResult[>..] = [];
    var failures: goosetest::Failure[>..] = [];
    var diagnostics: u8[>..] = [];
    var metadata: u8[>..] = [];
    var results = goosetest::new_results(cases, failures, diagnostics, metadata, limits);
    var t = goosetest::Test {
        results: results,
        ..
    };
    runtime_harness::run_cases(t, option == "--fail");
    if results.incomplete {
        write_stderr(goosetest::terminal_diagnostic(results));
        write_stderr("\n");
    }
    exit(goosetest::run_status(results));
}
