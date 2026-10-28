// Framework-owned rendering stops at byte limits; custom hooks remain user code.
namespace value_format_test;

import std;

import goosetest;
import test_support.runtime;

var calls: i64 = 0;
struct Value {
    number: i64
}
struct LargeValue {
    number: i64
}

fn format(out: u8[>..]&, value: Value) {
    calls += 1;
    ::format(out, value.number);
}

fn format(out: u8[>..]&, value: LargeValue) {
    calls += 1;
    for index in 0..1024 {
        out.push('x');
    }
}

fn test_large_text(outer: goosetest::Test&) {
    var large: u8[>..] = [];
    for index in 0..1048576 {
        large.push('x');
    }
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 64,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
            t.check_eq(large[..], "different");
        }
        assert(t.assertions == 1);
        assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        assert(t.results.diagnostics.len == 0);
        assert(t.results.failures.len == 0);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_collection_stops_formatting(outer: goosetest::Test&) {
    var expected: Value[>..] = [];
    var actual: Value[>..] = [];
    for index in 0..10000 {
        expected.push(Value {
                number: 12345
            });
        actual.push(Value {
                number: 12346
            });
    }
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 64,
            ..
        }) {
        t =>
        calls = 0;
        goosetest::execute_case(t) {
            t.assert_eq(expected[..], expected[..]);
        }
        assert(calls == 0);
        goosetest::execute_case(t) {
            t.assert_eq(expected[..], actual[..]);
        }
        assert(calls > 0);
        assert(calls < 10);
        assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        assert(t.results.diagnostics.len == 0);
        assert(t.results.failures.len == 0);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_custom_hook_limit(outer: goosetest::Test&) {
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 64,
            ..
        }) {
        t =>
        calls = 0;
        goosetest::execute_case(t) {
            t.assert_eq(LargeValue {
                    number: 1
                }, LargeValue {
                    number: 2
                });
        }
        assert(calls == 1);
        assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        assert(t.results.diagnostics.len == 0);
        assert(t.results.failures.len == 0);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_nested_arrays(outer: goosetest::Test&) {
    let expected: i64[2][2] = [[1, 2], [3, 4]];
    let actual: i64[2][2] = [[1, 2], [3, 5]];
    let text = "expected: <[[1, 2], [3, 4]]> actual: <[[1, 2], [3, 5]]>\n";
    let budgets: i64[2] = [text.len, text.len - 1];
    for budget in budgets {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            goosetest::execute_case(t) {
                t.check_eq(expected, actual);
            }
            if budget == text.len {
                assert(t.results.diagnostics == text);
                assert(goosetest::run_status(t.results) == 1);
            } else {
                assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
                assert(t.results.diagnostics.len == 0);
                assert(goosetest::run_status(t.results) == 2);
            }
        }
    }
}

fn test_array_storage_and_bytes(outer: goosetest::Test&) {
    let expected: i64[3] = [1, 2, 3];
    var actual: i64[3] = [1, 2, 4];
    var grown_expected: i64[>..] = [1, 2, 3];
    var grown_actual: i64[>..] = [1, 2, 4];
    let bytes_expected: u8[3] = ['a', 0, 'b'];
    var bytes_actual: u8[3] = ['a', 0, 'c'];
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.check_eq(expected, actual);
            t.check_eq(grown_expected, grown_actual);
            t.check_eq(bytes_expected, bytes_actual);
        }
        let oracle = str("expected: <", expected, "> actual: <", actual, ">\n",
            "expected: <", grown_expected, "> actual: <", grown_actual, ">\n",
            "expected: <", bytes_expected, "> actual: <", bytes_actual, ">\n");
        assert(t.results.diagnostics == oracle);
        assert(t.failures == 3);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_nested_byte_escaping(outer: goosetest::Test&) {
    let expected: const u8[:][2] = ["a\0\n\r\t\"\\z", "same"];
    let actual: const u8[:][2] = ["other", "same"];
    let oracle = str("expected: <", expected, "> actual: <", actual, ">\n");
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: oracle.len,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
            t.assert_eq(expected, actual);
        }
        assert(t.results.diagnostics == oracle);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_scalar_format_hooks(outer: goosetest::Test&) {
    let maximum: u64 = 18446744073709551615;
    let zero: u64 = 0;
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.check_eq(true, false);
            t.check_eq(maximum, zero);
        }
        let oracle = str("expected: <", true, "> actual: <", false, ">\n",
            "expected: <", maximum, "> actual: <", zero, ">\n");
        assert(t.results.diagnostics == oracle);
        assert(t.failures == 2);
        assert(goosetest::run_status(t.results) == 1);
    }
}
