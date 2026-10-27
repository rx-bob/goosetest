// Compare top-level fields in declaration order, recording one bounded failure per assertion.
namespace goosetest;

import src.runtime.context;
import src.runtime.diagnostics;
import src.runtime.execution;
import src.runtime.results;
import src.runtime.value_format;

fn assert_struct_eq<T>(t: Test&, expected: const T&, actual: const T&, message: u8[:] = "") {
    t.assertions += 1;
    var different = false;
    const for < N,
    A > in fields<T> {
        if expected.A != actual.A {
            different = true;
        }
    }
    if different {
        record_struct(t, expected, actual, message);
        return from goosetest::run_case;
    }
}

fn record_struct<T>(t: Test&, expected: const T&, actual: const T&, message: u8[:]) -> bool {
    let header = "struct fields differ:\n";
    if !can_format(t, message, header.len) {
        return false;
    }
    let limit = t.results.limits.diagnostic_bytes - t.results.diagnostics.len;
    var text: u8[>..] = [];
    format_message(text, message);
    text.append(header);
    const for < N,
    A > in fields<T> {
        if expected.A != actual.A {
            if !append_field(text, N, expected.A, actual.A, limit) {
                stop_run(t.results, TerminalError.DiagnosticLimit);
                return false;
            }
        }
    }
    return commit_failure(t, text);
}

fn append_field<T>(text: u8[>..]&, name: u8[:], expected: const T&, actual: const T&, limit: i64) -> bool {
    let label = " expected: <";
    let separator = "> actual: <";
    let suffix = ">\n";
    let envelope = 1 + name.len + label.len + separator.len + suffix.len;
    if envelope > limit - text.len {
        return false;
    }
    text.push('.');
    text.append(name);
    text.append(label);
    if !value_format::append(text, expected, limit - separator.len - suffix.len) {
        return false;
    }
    text.append(separator);
    if !value_format::append(text, actual, limit - suffix.len) {
        return false;
    }
    text.append(suffix);
    return true;
}
