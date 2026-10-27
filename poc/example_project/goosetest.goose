import std;
import os;

// ============================================================================
// goosetest: JUnit-Style Runtime Library for Goose
// ============================================================================
// Note on Goose UFCS (Spec §11.1):
// UFCS (`t.assert_eq(...)`) resolves in the caller's namespace and then the
// global namespace. Declaring `Test` and `assert_*` in the global namespace
// (matching `std`, `os`, and `vec`) lets any `namespace foo_test;` use UFCS
// `t.assert_eq(...)` and `t.assert_struct_eq(...)` directly!

struct FailureSpan {
    suite_idx: i64,
    offset: i64,
    len: i64,
}

struct Test {
    suite_name: const u8[:] = "",
    src_path: const u8[:] = "",
    test_path: const u8[:] = "",
    current_fn: const u8[:] = "",
    display_name: const u8[:] = "",
    failed: bool = false,
    assertions: i64 = 0,

    // Suite-level counters
    suite_passed: i64 = 0,
    suite_failed: i64 = 0,
    suite_skipped: i64 = 0,

    // Global totals across all mirrored test files
    total_suites: i64 = 0,
    total_passed: i64 = 0,
    total_failed: i64 = 0,
    total_skipped: i64 = 0,
    total_assertions: i64 = 0,
    start_ns: i64 = 0,
    case_start_ns: i64 = 0,

    failure_spans: FailureSpan[..128] = [],
    log_buf: u8[>..],
}

fn new_runner() -> Test {
    return Test {
        start_ns: clock_ns(),
        log_buf: [],
        ..
    };
}

// --- Internal Unwind Target (`return from run_case`) ------------------------

fn run_case<F>(t: Test&) {
    F();
}

// --- JUnit Lifecycle Orchestration ------------------------------------------

fn begin_suite(t: Test&, suite_name: const u8[:], src_path: const u8[:], test_path: const u8[:]) {
    t.suite_name = suite_name;
    t.src_path = src_path;
    t.test_path = test_path;
    t.suite_passed = 0;
    t.suite_failed = 0;
    t.suite_skipped = 0;
    t.total_suites += 1;
    print("┌─ ", suite_name, "  [", src_path, " <- ", test_path, "]");
}

fn end_suite(t: Test&) {
    print("└─ ", t.suite_passed, " passed, ", t.suite_failed, " failed, ", t.suite_skipped, " skipped\n");
}

fn skip_case(t: Test&, fn_name: const u8[:], display_name: const u8[:], reason: const u8[:]) {
    t.suite_skipped += 1;
    t.total_skipped += 1;
    let label = if display_name.len > 0 { display_name } else { fn_name };
    print("│  ↷ ", label, " (@Disabled: ", reason, ")");
}

fn begin_case(t: Test&, fn_name: const u8[:], display_name: const u8[:]) {
    t.current_fn = fn_name;
    t.display_name = if display_name.len > 0 { display_name } else { fn_name };
    t.failed = false;
    t.case_start_ns = clock_ns();
}

fn end_case(t: Test&, repeats: i64 = 1) {
    let elapsed_us = (clock_ns() - t.case_start_ns) / 1000;
    if t.failed {
        t.suite_failed += 1;
        t.total_failed += 1;
        print("│  ✗ ", t.display_name, " (", elapsed_us, " us)");
    } else {
        t.suite_passed += 1;
        t.total_passed += 1;
        if repeats > 1 {
            print("│  ✓ ", t.display_name, " [x", repeats, "] (", elapsed_us, " us)");
        } else {
            print("│  ✓ ", t.display_name, " (", elapsed_us, " us)");
        }
    }
}

// --- Failure Recording Helpers ----------------------------------------------

fn begin_failure(t: Test&) -> i64 {
    t.failed = true;
    let start = t.log_buf.len;
    format(t.log_buf, "  [FAIL] ", t.suite_name, " :: ", t.current_fn, " (\"", t.display_name, "\")\n",
                      "         Source: ", t.src_path, " | Test: ", t.test_path, "\n",
                      "         ");
    return start;
}

fn end_failure(t: Test&, start: i64) {
    t.log_buf.push('\n');
    if t.failure_spans.len < t.failure_spans.cap {
        t.failure_spans.push(FailureSpan {
            suite_idx: t.total_suites,
            offset: start,
            len: t.log_buf.len - start,
        });
    }
}

// --- JUnit Assertions (`assert_eq`, `assert_true`, `assert_struct_eq`, ...) -

fn fail(t: Test&, message: const u8[:]) {
    let start = begin_failure(t);
    format(t.log_buf, "AssertionFailedError: ", message);
    end_failure(t, start);
    return from run_case;
}

fn assert_true(t: Test&, cond: bool, message: const u8[:] = "expected: <true> but was: <false>") {
    t.assertions += 1;
    t.total_assertions += 1;
    if !cond {
        let start = begin_failure(t);
        format(t.log_buf, "AssertionFailedError: ", message);
        end_failure(t, start);
        return from run_case;
    }
}

fn assert_false(t: Test&, cond: bool, message: const u8[:] = "expected: <false> but was: <true>") {
    t.assertions += 1;
    t.total_assertions += 1;
    if cond {
        let start = begin_failure(t);
        format(t.log_buf, "AssertionFailedError: ", message);
        end_failure(t, start);
        return from run_case;
    }
}

fn assert_eq<T>(t: Test&, expected: T, actual: T, message: const u8[:] = "") {
    t.assertions += 1;
    t.total_assertions += 1;
    if !(expected == actual) {
        let start = begin_failure(t);
        if message.len > 0 {
            format(t.log_buf, "AssertionFailedError: ", message, " ==> ");
        } else {
            t.log_buf.append("AssertionFailedError: ");
        }
        format(t.log_buf, "expected: <", expected, "> but was: <", actual, ">");
        end_failure(t, start);
        return from run_case;
    }
}

fn assert_ne<T>(t: Test&, unexpected: T, actual: T, message: const u8[:] = "") {
    t.assertions += 1;
    t.total_assertions += 1;
    if unexpected == actual {
        let start = begin_failure(t);
        if message.len > 0 {
            format(t.log_buf, "AssertionFailedError: ", message, " ==> ");
        } else {
            t.log_buf.append("AssertionFailedError: ");
        }
        format(t.log_buf, "expected: not equal but was: <", actual, ">");
        end_failure(t, start);
        return from run_case;
    }
}

// Soft JUnit `assertAll`-style check: records failure without unwinding the test
fn check_eq<T>(t: Test&, expected: T, actual: T, message: const u8[:] = "") {
    t.assertions += 1;
    t.total_assertions += 1;
    if !(expected == actual) {
        let start = begin_failure(t);
        if message.len > 0 {
            format(t.log_buf, "MultipleFailuresError: ", message, " ==> ");
        } else {
            t.log_buf.append("MultipleFailuresError: ");
        }
        format(t.log_buf, "expected: <", expected, "> but was: <", actual, ">");
        end_failure(t, start);
    }
}

fn assert_struct_eq<T>(t: Test&, expected: T&, actual: T&, message: const u8[:] = "") {
    t.assertions += 1;
    t.total_assertions += 1;
    var diff_count = 0;
    const for <N, A> in fields<T> {
        if !(expected.A == actual.A) {
            diff_count += 1;
        }
    }
    if diff_count > 0 {
        let start = begin_failure(t);
        if message.len > 0 {
            format(t.log_buf, "AssertionFailedError: ", message, " (", diff_count, " field(s) differed):");
        } else {
            format(t.log_buf, "AssertionFailedError (", diff_count, " field(s) differed):");
        }
        const for <N, A> in fields<T> {
            if !(expected.A == actual.A) {
                format(t.log_buf, "\n           .", N, " ==> expected: <", expected.A, "> but was: <", actual.A, ">");
            }
        }
        end_failure(t, start);
        return from run_case;
    }
}

fn summary(t: Test&) -> i32 {
    let elapsed_ms = (clock_ns() - t.start_ns) / 1000000;
    if t.failure_spans.len > 0 {
        print("═══════════════════════════ Failures ═══════════════════════════");
        for span in t.failure_spans {
            write_stdout(t.log_buf[span.offset..span.offset + span.len]);
        }
    }
    print("═════════════════════════ JUnit Summary ════════════════════════");
    print("Suites:     ", t.total_suites, " executed");
    print("Tests:      ", t.total_passed, " passed, ", t.total_failed, " failed, ", t.total_skipped, " skipped");
    print("Assertions: ", t.total_assertions, " checked in ", elapsed_ms, " ms");
    print("════════════════════════════════════════════════════════════════");
    return if t.total_failed == 0 { 0 } else { 1 };
}
