// Outer coordination finalizes retained results after the recovery boundary returns.
namespace goosetest;

import src.runtime.context;
import src.runtime.metadata;
import src.runtime.results;

fn execute_case<F>(t: Test&, identity: CaseIdentity = CaseIdentity {
    }) {
    reset(t);
    t.current_case = reserve_case(t.results, identity);
    if t.current_case < 0 {
        return;
    }
    t.active = true;
    t.results.active = true;
    run_case(t) {
        F();
    }
    finish_case(t);
}

// Assertions return here, never past the outer coordinator's finalization.
fn run_case<F>(t: Test&) {
    assert(t.active);
    F();
}

fn finish_case(t: Test&) {
    assert(t.active);
    let result .= t.results.cases[t.current_case];
    result.assertions = t.assertions;
    result.failure_count = t.failures;
    result.diagnostics = Span {
        offset: t.diagnostic_start,
        length: t.results.diagnostics.len - t.diagnostic_start,
    };
    result.outcome = Outcome.Passed;
    if t.failures > 0 {
        result.outcome = Outcome.Failed;
    }
    if t.results.incomplete {
        result.outcome = Outcome.RunnerError;
    }
    count_outcome(t.results.totals, result.outcome);
    t.results.totals.assertions += t.assertions;
    t.active = false;
    t.results.active = false;
}

fn skip_case(results: Results&, identity: CaseIdentity, reason: u8[:]) {
    let index = reserve_case(results, identity, reason);
    if index < 0 {
        return;
    }
    results.cases[index].outcome = Outcome.Skipped;
    count_outcome(results.totals, Outcome.Skipped);
}
