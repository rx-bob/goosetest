// Stream identities and failures without allocating an escaped whole-report buffer.
namespace reporting;

import std;

import src.reporting.formatting;
import src.runtime.results;

fn identity<F>(results: goosetest::Results&, id: goosetest::CaseId) {
    escape(goosetest::metadata_text(results, id.test_path)) {
        text => F(text);
    }
    F("::");
    escape(goosetest::metadata_text(results, id.namespace_name)) {
        text => F(text);
    }
    F("::");
    escape(goosetest::metadata_text(results, id.function_name)) {
        text => F(text);
    }
    F(" (");
    escape(goosetest::metadata_text(results, id.test_path)) {
        text => F(text);
    }
    F(str(":", id.declaration_line, ")")[..]);
}

fn case_row<F>(results: goosetest::Results&, result: goosetest::CaseResult) {
    F(outcome_label(result.outcome));
    F(" ");
    identity(results, result.identity) {
        text => F(text);
    }
    F("\n");
    if result.identity.display_name.length > 0 {
        F("  display: ");
        escape(goosetest::metadata_text(results, result.identity.display_name)) {
            text => F(text);
        }
        F("\n");
    }
    if result.outcome == goosetest::Outcome.Skipped || result.outcome == goosetest::Outcome.NotRun {
        F("  reason: ");
        escape(goosetest::metadata_text(results, result.skip_reason)) {
            text => F(text);
        }
        F("\n");
    }
}

fn suite_phase(phase: goosetest::Phase) -> bool {
    return phase == goosetest::Phase.SuiteSetup || phase == goosetest::Phase.SuiteCleanup;
}

fn failure_rows<F>(results: goosetest::Results&, indices: i64[:], suite: bool) {
    var heading = false;
    for index in indices {
        let result = results.cases[index];
        for offset in 0..result.failure_count {
            let failure = results.failures[result.first_failure + offset];
            if suite_phase(failure.phase) == suite {
                if !heading {
                    if suite {
                        F("Suite-hook errors:\n");
                    }
                    else {
                        F("Failures:\n");
                    }
                    heading = true;
                }
                F("  ");
                identity(results, result.identity) {
                    text => F(text);
                }
                F(str(" [", phase_label(failure.phase), "]\n    ")[..]);
                escape(goosetest::diagnostic_text(results, failure.message)) {
                    text => F(text);
                }
                F("\n");
            }
        }
    }
}

// Standalone hooks carry owned identities without fabricating case outcomes.
fn suite_failure_rows<F>(results: goosetest::Results&, indices: i64[:], heading: bool) {
    if indices.len > 0 && !heading {
        F("Suite-hook errors:\n");
    }
    for index in indices {
        let failure = results.failures[index];
        F("  ");
        identity(results, failure.identity) {
            text => F(text);
        }
        F(str(" [", phase_label(failure.phase), "]\n    ")[..]);
        escape(goosetest::diagnostic_text(results, failure.message)) {
            text => F(text);
        }
        F("\n");
    }
}
