// Outer coordination finalizes retained results after the recovery boundary returns.
namespace goosetest;

import src.runtime.context;
import src.runtime.metadata;
import src.runtime.results;

fn execute_case<F>(t: Test&, identity: CaseIdentity = CaseIdentity {
    }) {
    if !begin_case(t, identity) {
        return;
    }
    run_case(t) {
        F();
    }
    finish_case(t);
}

// Fixture owners live inside F until all separately recovered phases finish.
fn execute_fixture<F>(t: Test&, identity: CaseIdentity = CaseIdentity {
    }) {
    if !begin_case(t, identity) {
        return;
    }
    F();
    finish_case(t);
}

fn begin_case(t: Test&, identity: CaseIdentity) -> bool {
    reset(t);
    t.current_case = reserve_case(t.results, identity);
    if t.current_case < 0 {
        return false;
    }
    t.active = true;
    t.results.active = true;
    return true;
}

// Cleanup may still be attempted after a resource error; no phase resets earlier failures.
fn run_phase<F>(t: Test&, phase: Phase) -> bool {
    assert(t.active);
    let previous_phase = t.phase;
    let failures_before = t.failures;
    t.phase = phase;
    run_case(t) {
        F();
    }
    t.phase = previous_phase;
    return t.failures == failures_before && !t.results.incomplete;
}

// Suite hooks own failures and metadata without reserving an ordinary case record.
fn run_suite_hook<F>(t: Test&, identity: CaseIdentity, phase: Phase, executable: bool = true) -> bool {
    assert( !t.active && !t.results.active);
    assert(phase == Phase.SuiteSetup || phase == Phase.SuiteCleanup);
    if !executable {
        return true;
    }
    reset(t);
    if t.results.incomplete && phase != Phase.SuiteCleanup {
        return false;
    }
    if !t.results.incomplete {
        if metadata_fits(t.results, identity, "") {
            t.suite_identity = own_identity(t.results, identity);
        } else {
            stop_run(t.results, TerminalError.MetadataLimit);
            if phase != Phase.SuiteCleanup {
                return false;
            }
        }
    }
    t.suite_hook = true;
    t.phase = phase;
    t.active = true;
    t.results.active = true;
    t.results.active_suite = true;
    run_case(t) {
        F();
    }
    t.results.totals.assertions += t.assertions;
    t.results.totals.suite_assertions += t.assertions;
    if t.failures > 0 {
        t.results.totals.suite_failures += 1;
        if t.results.fail_fast {
            t.results.fail_fast_stop = true;
        }
    }
    t.active = false;
    t.results.active = false;
    t.results.active_suite = false;
    t.suite_hook = false;
    t.phase = Phase.Body;
    return t.failures == 0 && !t.results.incomplete;
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
    if t.results.fail_fast && result.outcome == Outcome.Failed {
        t.results.fail_fast_stop = true;
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

// Selected executable cases stopped by policy are distinct from disabled/setup skips.
fn not_run_case(results: Results&, identity: CaseIdentity, reason: u8[:] = "fail-fast") {
    let index = reserve_case(results, identity, reason);
    if index < 0 {
        return;
    }
    results.cases[index].outcome = Outcome.NotRun;
    count_outcome(results.totals, Outcome.NotRun);
}
