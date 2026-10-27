// Retained results borrow caller-owned tables and byte arenas; no renderer required.
namespace goosetest;

struct Limits {
    cases: i64 = 4096,
    failures: i64 = 16384,
    diagnostic_bytes: i64 = 1048576,
    metadata_bytes: i64 = 1048576,
}
struct Span {
    offset: i64 = 0,
    length: i64 = 0
}
// Input views are copied before execution; retained CaseId contains only offsets.
struct CaseIdentity {
    test_path: const u8[:] = "",
    namespace_name: const u8[:] = "",
    function_name: const u8[:] = "",
    display_name: const u8[:] = "",
    declaration_line: i64 = 0,
}
struct CaseId {
    test_path: Span,
    namespace_name: Span,
    function_name: Span,
    display_name: Span,
    declaration_line: i64,
}
enum Outcome {
    Passed,
    Failed,
    Skipped,
    NotRun,
    RunnerError
}
enum Phase {
    Setup,
    Body,
    Cleanup,
    SuiteSetup,
    SuiteCleanup
}
enum TerminalError {
    None,
    InvalidLimits,
    CaseLimit,
    FailureLimit,
    DiagnosticLimit,
    MetadataLimit
}
struct Failure {
    phase: Phase,
    message: Span,
    is_suite: bool = false,
    identity: CaseId = CaseId {
        ..
    },
}
struct CaseResult {
    identity: CaseId,
    outcome: Outcome = Outcome.RunnerError,
    assertions: i64 = 0,
    first_failure: i64 = 0,
    failure_count: i64 = 0,
    diagnostics: Span = Span {
    },
    // Omission reason for either Skipped or NotRun.
    skip_reason: Span = Span {
    },
}
struct Totals {
    passed: i64 = 0,
    failed: i64 = 0,
    skipped: i64 = 0,
    runner_errors: i64 = 0,
    filtered: i64 = 0,
    not_run: i64 = 0,
    assertions: i64 = 0,
    suite_assertions: i64 = 0,
    suite_failures: i64 = 0,
}
struct Results {
    cases: CaseResult[>..]&,
    failures: Failure[>..]&,
    diagnostics: u8[>..]&,
    metadata: u8[>..]&,
    limits: Limits,
    totals: Totals = Totals {
    },
    terminal: TerminalError = TerminalError.None,
    incomplete: bool = false,
    active: bool = false,
    active_suite: bool = false,
    fail_fast: bool = false,
    fail_fast_stop: bool = false,
}

fn new_results(
    cases: CaseResult[>..]&,
    failures: Failure[>..]&,
    diagnostics: u8[>..]&,
    metadata: u8[>..]&,
    limits: Limits = Limits {
    }
) -> Results {
    assert(cases.len == 0);
    assert(failures.len == 0);
    assert(diagnostics.len == 0);
    assert(metadata.len == 0);
    var results = Results {
        cases: cases,
        failures: failures,
        diagnostics: diagnostics,
        metadata: metadata,
        limits: limits,
        ..
    };
    if limits.cases < 0 || limits.failures < 0 || limits.diagnostic_bytes < 0 || limits.metadata_bytes < 0 {
        stop_run(results, TerminalError.InvalidLimits);
    }
    return results;
}

fn stop_run(results: Results&, error: TerminalError) {
    if !results.incomplete {
        results.terminal = error;
    }
    results.incomplete = true;
}

fn run_status(results: Results&) -> i32 {
    if results.incomplete || results.active || results.cases.len == 0 {
        return 2;
    }
    if results.totals.runner_errors > 0 {
        return 2;
    }
    if results.totals.failed > 0 || results.totals.suite_failures > 0 {
        return 1;
    }
    if results.totals.not_run > 0 {
        return 2;
    }
    return 0;
}

// Static literals remain readable even when every arena has reached its limit.
fn terminal_diagnostic(results: Results&) -> const u8[:] {
    match results.terminal {
        InvalidLimits => {
            return "incomplete run: limits must be nonnegative";
        },
        CaseLimit => {
            return "incomplete run: case record limit exhausted";
        },
        FailureLimit => {
            return "incomplete run: failure record limit exhausted";
        },
        DiagnosticLimit => {
            return "incomplete run: diagnostic byte limit exhausted";
        },
        MetadataLimit => {
            return "incomplete run: metadata byte limit exhausted";
        },
        None => {
        },
    }
    if results.active_suite {
        return "incomplete run: suite hook execution is still active";
    }
    if results.active {
        return "incomplete run: case execution is still active";
    }
    if results.cases.len == 0 {
        return "no cases executed or skipped";
    }
    return "";
}

fn count_outcome(totals: Totals&, outcome: Outcome) {
    match outcome {
        Passed => {
            totals.passed += 1;
        },
        Failed => {
            totals.failed += 1;
        },
        Skipped => {
            totals.skipped += 1;
        },
        NotRun => {
            totals.not_run += 1;
        },
        RunnerError => {
            totals.runner_errors += 1;
        },
    }
}

// Filtered inventory consumes no executed/skipped case record.
fn record_filtered(results: Results&) {
    results.totals.filtered += 1;
}

fn metadata_text(results: Results&, span: Span) -> const u8[:] {
    return results.metadata[span.offset..span.offset + span.length];
}

fn diagnostic_text(results: Results&, span: Span) -> const u8[:] {
    return results.diagnostics[span.offset..span.offset + span.length];
}
