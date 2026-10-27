// Containment and tolerance diagnostics preserve labels and the caller's optional message.
namespace goosetest;

import math;

import src.runtime.context;
import src.runtime.diagnostics;
import src.runtime.results;
import src.runtime.value_format;

fn record_contains(t: Test&, expected: u8[:], actual: u8[:], message: u8[:]) -> bool {
    let envelope = "expected fragment: <> actual: <>\n";
    if !can_format(t, message, envelope.len) {
        return false;
    }
    let limit = t.results.limits.diagnostic_bytes - t.results.diagnostics.len;
    var text: u8[>..] = [];
    format_message(text, message);
    text.append("expected fragment: <");
    if !value_format::append(text, expected, limit - "> actual: <>\n".len) {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    text.append("> actual: <");
    if !value_format::append(text, actual, limit - ">\n".len) {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    text.append(">\n");
    return commit_failure(t, text);
}

fn record_near(t: Test&, expected: f64, actual: f64, tolerance: f64, message: u8[:]) -> bool {
    let invalid = !(tolerance >= 0.0) || is_inf(tolerance);
    var reason: const u8[:] = "";
    if invalid {
        reason = "tolerance must be finite and nonnegative\n";
    }
    let envelope = "expected: <> actual: <> absolute tolerance: <>\n";
    if !can_format(t, message, envelope.len + reason.len) {
        return false;
    }
    let limit = t.results.limits.diagnostic_bytes - t.results.diagnostics.len - reason.len;
    var text: u8[>..] = [];
    format_message(text, message);
    text.append("expected: <");
    if !value_format::append(text, expected, limit - "> actual: <> absolute tolerance: <>\n".len) {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    text.append("> actual: <");
    if !value_format::append(text, actual, limit - "> absolute tolerance: <>\n".len) {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    text.append("> absolute tolerance: <");
    if !value_format::append(text, tolerance, limit - ">\n".len) {
        stop_run(t.results, TerminalError.DiagnosticLimit);
        return false;
    }
    text.append(">\n");
    text.append(reason);
    return commit_failure(t, text);
}
