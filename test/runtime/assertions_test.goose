// Exercise the public assertion vocabulary using independent builtin assertions.
namespace assertions_test;

import goosetest;
import goosetest.test_support.runtime;

import std;

var formatted_values: i64 = 0;

struct Value {
    number: i64,
}

fn format(out: u8[>..]&, value: Value) {
    formatted_values += 1;
    ::format(out, "value=", value.number);
}

fn test_passing_values() {
    runtime_support::with_test() {
        t =>
        var text: u8[>..] = [];
        text.append("goose");
        var values: i64[>..] = [1, 2, 3];
        let expected: i64[3] = [1, 2, 3];
        goosetest::execute_case(t) {
            t.assert_true(true);
            t.assert_false(false);
            t.assert_eq(12, 12);
            t.assert_eq(1.5, 1.5);
            t.assert_eq("goose", text[..]);
            t.assert_eq(text[..], "goose");
            t.assert_eq(expected[..], values[..]);
            t.assert_ne(1, 2);
            t.assert_ne("duck", text[..]);
            t.check_eq(expected[..], values[..], text);
        }
        assert(t.assertions == 10);
        assert(t.failures == 0);
        assert(goosetest::case_diagnostics(t).len == 0);
    }
}

fn test_boolean_failures() {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.assert_true(false, "required");
            t.fail("unreachable");
        }
        assert(t.assertions == 1);
        assert(goosetest::case_diagnostics(t) == "required: expected: <true> actual: <false>\n");
        goosetest::execute_case(t) {
            t.assert_false(true);
            t.fail("unreachable");
        }
        assert(t.assertions == 1);
        assert(goosetest::case_diagnostics(t) == "expected: <false> actual: <true>\n");
    }
}

fn test_explicit_and_unequal_failures() {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.fail("stop here");
            t.fail("unreachable");
        }
        assert(t.assertions == 1);
        assert(t.failures == 1);
        assert(goosetest::case_diagnostics(t) == "stop here: explicit failure\n");
        goosetest::execute_case(t) {
            t.assert_ne(7, 7, "distinct");
            t.fail("unreachable");
        }
        assert(t.assertions == 1);
        assert(t.failures == 1);
        assert(goosetest::case_diagnostics(t) == "distinct: unexpected: <7> actual: <7>\n");
    }
}

fn test_failed_text_and_slices() {
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            var actual: u8[>..] = [];
            actual.append("actual");
            t.check_eq("expected", actual[..]);
            let expected: i64[2] = [1, 2];
            let different: i64[2] = [1, 3];
            t.check_eq(expected[..], different[..]);
        }
        assert(t.failures == 2);
        let expected = "expected: <expected> actual: <actual>\nexpected: <[1, 2]> actual: <[1, 3]>\n";
        assert(goosetest::case_diagnostics(t) == expected);
    }
}

fn test_format_hooks() {
    runtime_support::with_test() {
        t =>
        let first = Value {
            number: 1
        };
        let second = Value {
            number: 2
        };
        formatted_values = 0;
        goosetest::execute_case(t) {
            t.assert_eq(first, first);
            t.assert_ne(first, second);
            t.check_eq(second, second);
        }
        assert(formatted_values == 0);
        assert(t.assertions == 3);
        assert(goosetest::case_diagnostics(t).len == 0);
        goosetest::execute_case(t) {
            t.assert_eq(first, second, "custom");
        }
        assert(formatted_values == 2);
        assert(goosetest::case_diagnostics(t) == "custom: expected: <value=1> actual: <value=2>\n");
        goosetest::execute_case(t) {
            t.assert_ne(first, first);
        }
        assert(formatted_values == 4);
        assert(goosetest::case_diagnostics(t) == "unexpected: <value=1> actual: <value=1>\n");
    }
}

fn test_empty_and_different_length_slices() {
    runtime_support::with_test() {
        t =>
        let empty: i64[0] = [];
        let single: i64[1] = [1];
        goosetest::execute_case(t) {
            t.assert_eq(empty[..], empty[..]);
            t.assert_ne(empty[..], single[..]);
            t.check_eq(empty[..], single[..]);
        }
        assert(t.assertions == 3);
        assert(t.failures == 1);
        assert(goosetest::case_diagnostics(t) == "expected: <[]> actual: <[1]>\n");
    }
}
