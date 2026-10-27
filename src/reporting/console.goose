// Plain-text reports consume finalized runtime records; the assertion runtime stays output-free.
namespace reporting;

import os;
import std;

import src.reporting.formatting;
import src.reporting.ordering;
import src.reporting.rows;
import src.runtime.results;

fn report(results: goosetest::Results&, planned_cases: i64 = - 1) {
    render(results, planned_cases) {
        text => write_stdout(text);
    }
}

fn render<F>(results: goosetest::Results&, planned_cases: i64 = - 1) {
    var indices: i64[>..] = [];
    var totals = goosetest::Totals {
    };
    var suite_errors: i64 = 0;
    for result,
    index in results.cases {
        // Execution reserves its final slot before running; never render an active outcome.
        if !results.active || index + 1 < results.cases.len {
            indices.push(index);
            goosetest::count_outcome(totals, result.outcome);
            totals.assertions += result.assertions;
            for offset in 0..result.failure_count {
                if suite_phase(results.failures[result.first_failure + offset].phase) {
                    suite_errors += 1;
                }
            }
        }
    }
    sort(indices) {
        a,
        b => case_less(results, a, b)
    };
    F("goosetest results (locations identify test declarations)\n");
    for index in indices {
        case_row(results, results.cases[index]) {
            text => F(text);
        }
    }
    failure_rows(results, indices, false) {
        text => F(text);
    }
    failure_rows(results, indices, true) {
        text => F(text);
    }
    var planned = planned_cases;
    if planned < 0 {
        planned = results.cases.len;
    }
    let not_run = max(0, planned - indices.len);
    summary(results, totals, not_run, suite_errors) {
        text => F(text);
    }
    if planned < results.cases.len {
        F("ERROR: planned case count is smaller than retained records; execution incomplete.\n");
    } else if results.incomplete || results.active || totals.runner_errors > 0 || not_run > 0 || indices.len == 0 {
        F("ERROR: execution incomplete");
        let diagnostic = goosetest::terminal_diagnostic(results);
        if diagnostic.len > 0 {
            F(": ");
            escape(diagnostic) {
                text => F(text);
            }
        }
        F(".\n");
    }
}

fn summary<F>(results: goosetest::Results&, totals: goosetest::Totals, not_run: i64, suite_errors: i64) {
    F(str("Cases: ", totals.passed, " passed, ", totals.failed, " failed, ", totals.skipped,
        " skipped, ", totals.runner_errors, " errors, ", not_run, " not run; ",
        results.totals.filtered, " filtered\n")[..]);
    F(str("Assertions: ", totals.assertions, "; suite-hook errors: ", suite_errors, "\n")[..]);
}
