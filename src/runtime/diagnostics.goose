// Commit complete failure text atomically after checking retained-storage budgets.
namespace goosetest;

import std;

import src.runtime.context;
import src.runtime.results;
import src.runtime.value_format;

fn failure_available(t: Test&) -> bool {
    assert(t.active);
    if t.results.incomplete {
        return false;
    }
    if t.results.failures.len >= t.results.limits.failures {
        stop_run(t.results, TerminalError.FailureLimit);
        return false;
    }
    return true;
}

fn commit_failure(t: Test&, text: u8[:]) -> bool {
    if !failure_available(t) {
        return false;
    }
    let remaining = t.results.limits.diagnostic_bytes - t.results.diagnostics.len;
    if text.len > remaining {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    let span = Span {
        offset: t.results.diagnostics.len,
        length: text.len
    };
    t.results.diagnostics.append(text);
    t.results.failures.push(Failure {
            phase: t.phase,
            message: span
        });
    t.failures += 1;
    return true;
}

fn format_message(out: u8[>..]&, message: u8[:]) {
    if message.len > 0 {
        format(out, message, ": ");
    }
}

// Reject text that cannot fit even before invoking user-controlled value formatters.
fn can_format(t: Test&, message: u8[:], envelope_bytes: i64) -> bool {
    if !failure_available(t) {
        return false;
    }
    var remaining = t.results.limits.diagnostic_bytes - t.results.diagnostics.len;
    var minimum_bytes = envelope_bytes;
    if message.len > 0 {
        minimum_bytes += 2;
    }
    if message.len > remaining {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    remaining -= message.len;
    if minimum_bytes > remaining {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    return true;
}

fn record_equality<T>(t: Test&, expected: T, actual: T, message: u8[:]) -> bool {
    return record_comparison(t, expected, actual, message, "expected: <");
}

fn record_inequality<T>(t: Test&, unexpected: T, actual: T, message: u8[:]) -> bool {
    return record_comparison(t, unexpected, actual, message, "unexpected: <");
}

fn record_comparison<T>(t: Test&, expected: T, actual: T, message: u8[:], label: u8[:]) -> bool {
    let separator = "> actual: <";
    let suffix = ">\n";
    if !can_format(t, message, label.len + separator.len + suffix.len) {
        return false;
    }
    let limit = t.results.limits.diagnostic_bytes - t.results.diagnostics.len;
    var text: u8[>..] = [];
    format_message(text, message);
    text.append(label);
    if !value_format::append(text, expected, limit - separator.len - suffix.len) {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    text.append(separator);
    if !value_format::append(text, actual, limit - suffix.len) {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    text.append(suffix);
    return commit_failure(t, text);
}

fn record_explicit(t: Test&, message: u8[:]) -> bool {
    if !can_format(t, message, "explicit failure\n".len) {
        return false;
    }
    var text: u8[>..] = [];
    format_message(text, message);
    text.append("explicit failure\n");
    return commit_failure(t, text);
}
