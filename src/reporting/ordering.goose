// Sort lightweight indices; record and arena collection order never changes identities.
namespace reporting;

import src.reporting.formatting;
import src.runtime.results;

fn compare_bytes(left: u8[:], right: u8[:]) -> i32 {
    var index: i64 = 0;
    while index < left.len && index < right.len {
        if left[index] < right[index] {
            return -1;
        }
        if left[index] > right[index] {
            return 1;
        }
        index += 1;
    }
    if left.len < right.len {
        return -1;
    }
    if left.len > right.len {
        return 1;
    }
    return 0;
}

fn case_less(results: goosetest::Results&, left: i64, right: i64) -> bool {
    let a = results.cases[left].identity;
    let b = results.cases[right].identity;
    let paths = compare_bytes(goosetest::metadata_text(results, a.test_path),
        goosetest::metadata_text(results, b.test_path));
    if paths != 0 {
        return paths < 0;
    }
    let spaces = compare_bytes(goosetest::metadata_text(results, a.namespace_name),
        goosetest::metadata_text(results, b.namespace_name));
    if spaces != 0 {
        return spaces < 0;
    }
    if a.declaration_line != b.declaration_line {
        return a.declaration_line < b.declaration_line;
    }
    let functions = compare_bytes(goosetest::metadata_text(results, a.function_name),
        goosetest::metadata_text(results, b.function_name));
    if functions != 0 {
        return functions < 0;
    }
    return tie_less(results, results.cases[left], results.cases[right]);
}

// Explicit harnesses may reuse identities; compare visible record contents as tie breakers.
fn tie_less(results: goosetest::Results&, a: goosetest::CaseResult, b: goosetest::CaseResult) -> bool {
    let display = compare_bytes(goosetest::metadata_text(results, a.identity.display_name),
        goosetest::metadata_text(results, b.identity.display_name));
    if display != 0 {
        return display < 0;
    }
    let labels = compare_bytes(outcome_label(a.outcome), outcome_label(b.outcome));
    if labels != 0 {
        return labels < 0;
    }
    let reasons = compare_bytes(goosetest::metadata_text(results, a.skip_reason),
        goosetest::metadata_text(results, b.skip_reason));
    if reasons != 0 {
        return reasons < 0;
    }
    if a.assertions != b.assertions {
        return a.assertions < b.assertions;
    }
    if a.failure_count != b.failure_count {
        return a.failure_count < b.failure_count;
    }
    for offset in 0..a.failure_count {
        let af = results.failures[a.first_failure + offset];
        let bf = results.failures[b.first_failure + offset];
        let phases = compare_bytes(phase_label(af.phase), phase_label(bf.phase));
        if phases != 0 {
            return phases < 0;
        }
        let messages = compare_bytes(goosetest::diagnostic_text(results, af.message),
            goosetest::diagnostic_text(results, bf.message));
        if messages != 0 {
            return messages < 0;
        }
    }
    return false;
}

fn suite_failure_less(results: goosetest::Results&, left: i64, right: i64) -> bool {
    let a = results.failures[left];
    let b = results.failures[right];
    let paths = compare_bytes(goosetest::metadata_text(results, a.identity.test_path),
        goosetest::metadata_text(results, b.identity.test_path));
    if paths != 0 {
        return paths < 0;
    }
    let spaces = compare_bytes(goosetest::metadata_text(results, a.identity.namespace_name),
        goosetest::metadata_text(results, b.identity.namespace_name));
    if spaces != 0 {
        return spaces < 0;
    }
    if a.phase != b.phase {
        return a.phase == goosetest::Phase.SuiteSetup;
    }
    if a.identity.declaration_line != b.identity.declaration_line {
        return a.identity.declaration_line < b.identity.declaration_line;
    }
    let functions = compare_bytes(goosetest::metadata_text(results, a.identity.function_name),
        goosetest::metadata_text(results, b.identity.function_name));
    if functions != 0 {
        return functions < 0;
    }
    return compare_bytes(goosetest::diagnostic_text(results, a.message),
        goosetest::diagnostic_text(results, b.message)) < 0;
}
