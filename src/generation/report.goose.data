// Minimal generated result view; full console reporting arrives in E5.
namespace goosetest_generated_report;

import goosetest;

import os;
import std;

fn report(results: goosetest::Results&) {
    for result in results.cases {
        let identity = result.identity;
        print(label(result.outcome), " ", goosetest::metadata_text(results, identity.test_path), "::",
            goosetest::metadata_text(results, identity.namespace_name), "::",
            goosetest::metadata_text(results, identity.function_name), " (",
            goosetest::metadata_text(results, identity.test_path), ":", identity.declaration_line, ")");
        write_stdout(goosetest::diagnostic_text(results, result.diagnostics));
    }
    if results.incomplete {
        print(goosetest::terminal_diagnostic(results));
    }
    print("Cases: ", results.totals.passed, " passed, ", results.totals.failed, " failed, ",
        results.totals.skipped, " skipped, ", results.totals.runner_errors, " errors");
}

fn label(outcome: goosetest::Outcome) -> const u8[:] {
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
        RunnerError => {
            return "ERROR";
        },
    }
}
