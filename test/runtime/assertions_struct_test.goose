// Top-level field diagnostics preserve declaration order and one-operation accounting.
namespace assertions_struct_test;

import std;

import goosetest;
import test_support.runtime;

struct Decision {
    allowed: bool,
    reason: const u8[:],
}
struct Nested {
    number: i64,
}
struct Envelope {
    nested: Nested,
    unchanged: i64,
}
struct Collection {
    numbers: const i64[:],
    label: const u8[:],
}
struct Empty {
}
struct NestedSlices {
    numbers: const i64[:],
}
struct SliceContainer {
    detail: NestedSlices,
}

var format_calls: i64 = 0;

fn format(out: u8[>..]&, value: Nested) {
    format_calls += 1;
    ::format(out, "nested=", value.number);
}

fn test_equal_and_const(outer: goosetest::Test&) {
    let expected = Decision {
        allowed: true,
        reason: "allowed"
    };
    let readonly: const Decision& = expected;
    var actual = Decision {
        allowed: true,
        reason: "allowed"
    };
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: 0,
            failures: 0,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
            t.assert_struct_eq(readonly, actual);
            let empty = Empty {
            };
            t.assert_struct_eq(empty, empty);
        }
        assert(t.assertions == 2);
        assert(t.failures == 0);
        assert(goosetest::run_status(t.results) == 0);
        assert(t.results.diagnostics.len == 0);
    }
}

fn test_multiple_and_single(outer: goosetest::Test&) {
    let expected = Decision {
        allowed: true,
        reason: "allowed"
    };
    var actual = Decision {
        allowed: false,
        reason: "viewer_cannot_write"
    };
    runtime_support::with_test() {
        t =>
        var reached = false;
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual, "permissions");
            reached = true;
        }
        assert(!reached);
        assert(t.assertions == 1);
        assert(t.failures == 1);
        assert(t.results.failures.len == 1);
        assert(t.results.totals.failed == 1);
        assert(goosetest::case_diagnostics(t) == str("permissions: struct fields differ:\n",
            ".allowed expected: <true> actual: <false>\n",
            ".reason expected: <allowed> actual: <viewer_cannot_write>\n"));
        actual.allowed = true;
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        assert(goosetest::case_diagnostics(t) == str("struct fields differ:\n",
            ".reason expected: <allowed> actual: <viewer_cannot_write>\n"));
        assert(t.results.failures.len == 2);
        assert(t.results.totals.failed == 2);
        actual.reason = "allowed";
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        assert(t.results.totals.passed == 1);
        assert(goosetest::run_status(t.results) == 1);
    }
}

fn test_nested_format_hook(outer: goosetest::Test&) {
    let expected = Envelope {
        nested: Nested {
            number: 1
        },
        unchanged: 7
    };
    var actual = expected;
    runtime_support::with_test() {
        t =>
        format_calls = 0;
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        assert(format_calls == 0);
        actual.nested.number = 2;
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        assert(format_calls == 2);
        assert(t.assertions == 1);
        assert(t.failures == 1);
        assert(goosetest::case_diagnostics(t) == str("struct fields differ:\n",
            ".nested expected: <nested=1> actual: <nested=2>\n"));
        assert(t.results.totals.passed == 1);
        assert(t.results.totals.failed == 1);
    }
}

fn test_slice_fields(outer: goosetest::Test&) {
    let first: i64[3] = [1, 2, 3];
    var second: i64[3] = [1, 2, 3];
    let expected = Collection {
        numbers: first[..],
        label: "kept"
    };
    let actual = Collection {
        numbers: second[..],
        label: "kept"
    };
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        second[2] = 4;
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        assert(t.assertions == 1);
        assert(t.failures == 1);
        assert(goosetest::case_diagnostics(t) == str("struct fields differ:\n",
            ".numbers expected: <[1, 2, 3]> actual: <[1, 2, 4]>\n"));
    }
}

fn test_struct_budget(outer: goosetest::Test&) {
    let expected = Decision {
        allowed: true,
        reason: "same"
    };
    let actual = Decision {
        allowed: false,
        reason: "same"
    };
    let text = "limit: struct fields differ:\n.allowed expected: <true> actual: <false>\n";
    let budgets: i64[2] = [text.len, text.len - 1];
    for budget in budgets {
        runtime_support::with_test(goosetest::Limits {
                diagnostic_bytes: budget,
                ..
            }) {
            t =>
            var reached = false;
            goosetest::execute_case(t) {
                t.assert_struct_eq(expected, actual, "limit");
                reached = true;
            }
            assert(!reached);
            assert(t.assertions == 1);
            if budget == text.len {
                assert(t.results.diagnostics == text);
                assert(t.failures == 1);
                assert(t.results.failures.len == 1);
                assert(goosetest::run_status(t.results) == 1);
            } else {
                assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
                assert(t.results.diagnostics.len == 0);
                assert(t.results.failures.len == 0);
                assert(goosetest::run_status(t.results) == 2);
            }
        }
    }
}

fn test_struct_limit_stops_hooks(outer: goosetest::Test&) {
    let expected = Envelope {
        nested: Nested {
            number: 1
        },
        unchanged: 7
    };
    let actual = Envelope {
        nested: Nested {
            number: 2
        },
        unchanged: 8
    };
    runtime_support::with_test(goosetest::Limits {
            failures: 0,
            ..
        }) {
        t =>
        format_calls = 0;
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        assert(format_calls == 0);
        assert(t.results.terminal == goosetest::TerminalError.FailureLimit);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_multifield_budget_atomicity(outer: goosetest::Test&) {
    let expected = Decision {
        allowed: true,
        reason: "allowed"
    };
    let actual = Decision {
        allowed: false,
        reason: "denied"
    };
    let first = "expected: <1> actual: <2>\n";
    let partial = "struct fields differ:\n.allowed expected: <true> actual: <false>\n";
    runtime_support::with_test(goosetest::Limits {
            diagnostic_bytes: first.len + partial.len,
            ..
        }) {
        t =>
        goosetest::execute_case(t) {
            t.check_eq(1, 2);
            t.assert_struct_eq(expected, actual);
        }
        assert(t.assertions == 2);
        assert(t.results.diagnostics == first);
        assert(t.results.failures.len == 1);
        assert(t.results.terminal == goosetest::TerminalError.DiagnosticLimit);
        assert(t.results.cases[0].outcome == goosetest::Outcome.RunnerError);
        assert(goosetest::run_status(t.results) == 2);
    }
}

fn test_nested_slice_identity(outer: goosetest::Test&) {
    var left: i64[2] = [1, 2];
    var right: i64[2] = [1, 2];
    let expected = NestedSlices {
        numbers: left[..]
    };
    let actual = NestedSlices {
        numbers: right[..]
    };
    let expected_container = SliceContainer {
        detail: expected
    };
    let actual_container = SliceContainer {
        detail: actual
    };
    assert(expected.numbers == actual.numbers);
    assert(expected != actual);
    runtime_support::with_test() {
        t =>
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected, actual);
        }
        assert(t.failures == 0);
        goosetest::execute_case(t) {
            t.assert_struct_eq(expected_container, actual_container);
        }
        assert(t.failures == 1);
        assert(t.results.failures.len == 1);
        let text = str("struct fields differ:\n.detail expected: <", expected,
            "> actual: <", actual, ">\n");
        assert(goosetest::case_diagnostics(t) == text);
        assert(t.results.totals.passed == 1);
        assert(t.results.totals.failed == 1);
    }
}
