// Current-case state borrows retained results; it owns no growable allocations.
namespace goosetest;

import src.runtime.results;

struct Test {
    results: Results&,
    assertions: i64 = 0,
    failures: i64 = 0,
    phase: Phase = Phase.Body,
    current_case: i64 = - 1,
    diagnostic_start: i64 = 0,
    active: bool = false,
}

fn reset(t: Test&) {
    assert( !t.active);
    t.assertions = 0;
    t.failures = 0;
    t.phase = Phase.Body;
    t.current_case = - 1;
    t.diagnostic_start = t.results.diagnostics.len;
}

fn case_status(t: Test&) -> i32 {
    if t.results.incomplete || t.active || t.current_case < 0 {
        return 2;
    }
    if t.failures > 0 {
        return 1;
    }
    return 0;
}

fn case_diagnostics(t: Test&) -> const u8[:] {
    if t.current_case < 0 {
        return "";
    }
    return diagnostic_text(t.results, t.results.cases[t.current_case].diagnostics);
}
