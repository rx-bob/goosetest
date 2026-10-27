import std;
import os;

// ============================================================================
// goosetest: Standardized Zero-Cost Testing Framework for Goose (PoC)
// ============================================================================
// Designed around Goose's core strengths:
//   1. Non-aborting assertions via `return from run_case` (Spec §20)
//   2. Universal value formatting via `format(out, v)` + compile-time struct
//      field diffing via `const for <N, A> in fields<T>` (Spec §16)
//   3. Single append-only diagnostic arena `log_buf: u8[>..]` (Spec §12–§14)
//   4. Hierarchical `describe` / `test` blocks via compile-time function
//      values (Spec §18) with nanosecond timing (`os::clock_ns`)
//   5. Built-in deterministic property testing (`std::rng`) & micro-benchmarks

struct FailureSpan {
    offset: i64,
    len: i64,
}

struct Suite {
    name: const u8[:],
    filter: const u8[:] = "",
    fail_fast: bool = false,
    verbose: bool = true,
    tap_format: bool = false,
    seed: u64 = 0x5EEDCAFE12345678,

    // Active breadcrumb stack for nested `describe` blocks (0 data stacks!)
    scopes: (const u8[:])[..8] = [],
    current_test: const u8[:] = "",
    current_failed: bool = false,
    current_checks: i64 = 0,
    aborted_early: bool = false,

    // Counters
    passed: i64 = 0,
    failed: i64 = 0,
    skipped: i64 = 0,
    total_assertions: i64 = 0,
    suite_start_ns: i64 = 0,

    // Append-only diagnostic buffer + fixed span index (only 1 data stack!)
    failure_spans: FailureSpan[..128] = [],
    log_buf: u8[>..],
}

fn new_suite(name: const u8[:]) -> Suite {
    var s = Suite {
        name: name,
        suite_start_ns: clock_ns(),
        log_buf: [],
        ..
    };
    return s;
}

// --- 1. Breadcrumb & Failure Recording --------------------------------------

fn format_breadcrumb(s: Suite&, out: u8[>..]&) {
    for scope_name, i in s.scopes {
        if i > 0 { out.append(" > "); }
        out.append(scope_name);
    }
    if s.scopes.len > 0 { out.append(" > "); }
    out.append(s.current_test);
}

fn begin_failure(s: Suite&) -> i64 {
    s.current_failed = true;
    let start = s.log_buf.len;
    s.log_buf.append("  [FAIL] ");
    format_breadcrumb(s, s.log_buf);
    s.log_buf.append("\n         ");
    return start;
}

fn end_failure(s: Suite&, start: i64) {
    s.log_buf.push('\n');
    if s.failure_spans.len < s.failure_spans.cap {
        s.failure_spans.push(FailureSpan { offset: start, len: s.log_buf.len - start });
    }
}

// --- 2. Test Execution Boundary (`return from run_case`) --------------------

fn run_case<F>(s: Suite&) {
    F();
}

inline fn describe<F>(s: Suite&, group_name: const u8[:]) {
    guard !s.aborted_early else { return; }
    if s.scopes.len < s.scopes.cap {
        s.scopes.push(group_name);
    }
    F();
    if s.scopes.len > 0 {
        s.scopes.pop();
    }
}

fn matches_filter(s: Suite&, test_name: const u8[:]) -> bool {
    guard s.filter.len > 0 else { return true; }
    if find(test_name, s.filter) >= 0 { return true; }
    for scope_name in s.scopes {
        if find(scope_name, s.filter) >= 0 { return true; }
    }
    return false;
}

inline fn test<F>(s: Suite&, test_name: const u8[:]) {
    guard !s.aborted_early else { return; }
    if !matches_filter(s, test_name) {
        s.skipped += 1;
        return;
    }
    s.current_test = test_name;
    s.current_failed = false;
    s.current_checks = 0;

    let t0 = clock_ns();
    run_case(s) {
        F();
    };
    let elapsed_us = (clock_ns() - t0) / 1000;

    let idx = s.passed + s.failed + 1;
    if s.current_failed {
        s.failed += 1;
        if s.tap_format {
            print("not ok ", idx, " - ", test_name);
        } else if s.verbose {
            print("  ✗ ", test_name, " (", elapsed_us, " us)");
        }
        if s.fail_fast {
            s.aborted_early = true;
        }
    } else {
        s.passed += 1;
        if s.tap_format {
            print("ok ", idx, " - ", test_name);
        } else if s.verbose {
            print("  ✓ ", test_name, " (", elapsed_us, " us)");
        }
    }
}

inline fn skip<F>(s: Suite&, test_name: const u8[:]) {
    s.skipped += 1;
    if s.verbose && !s.tap_format {
        print("  - ", test_name, " (skipped)");
    }
}

// --- 3. Rich Assertions (Hard `expect_*` & Soft `check_*`) ------------------

fn fail(s: Suite&, message: const u8[:]) {
    let start = begin_failure(s);
    s.log_buf.append("fail: ");
    s.log_buf.append(message);
    end_failure(s, start);
    return from run_case;
}

fn expect_true(s: Suite&, cond: bool, label: const u8[:] = "expected true, got false") {
    s.total_assertions += 1;
    if !cond {
        let start = begin_failure(s);
        s.log_buf.append(label);
        end_failure(s, start);
        return from run_case;
    }
}

fn expect_false(s: Suite&, cond: bool, label: const u8[:] = "expected false, got true") {
    s.total_assertions += 1;
    if cond {
        let start = begin_failure(s);
        s.log_buf.append(label);
        end_failure(s, start);
        return from run_case;
    }
}

fn expect_eq<T>(s: Suite&, actual: T, expected: T, label: const u8[:] = "expect_eq") {
    s.total_assertions += 1;
    if !(actual == expected) {
        let start = begin_failure(s);
        format(s.log_buf, label, ": actual `", actual, "` != expected `", expected, "`");
        end_failure(s, start);
        return from run_case;
    }
}

fn check_eq<T>(s: Suite&, actual: T, expected: T, label: const u8[:] = "check_eq") {
    s.total_assertions += 1;
    if !(actual == expected) {
        let start = begin_failure(s);
        format(s.log_buf, label, " (soft): actual `", actual, "` != expected `", expected, "`");
        end_failure(s, start);
    }
}

fn expect_ne<T>(s: Suite&, actual: T, unexpected: T, label: const u8[:] = "expect_ne") {
    s.total_assertions += 1;
    if actual == unexpected {
        let start = begin_failure(s);
        format(s.log_buf, label, ": expected value != `", unexpected, "`");
        end_failure(s, start);
        return from run_case;
    }
}

fn expect_near(s: Suite&, actual: f64, expected: f64, eps: f64, label: const u8[:] = "expect_near") {
    s.total_assertions += 1;
    let diff = abs(actual - expected);
    if diff > eps {
        let start = begin_failure(s);
        format(s.log_buf, label, ": |", actual, " - ", expected, "| = ", diff, " > ", eps);
        end_failure(s, start);
        return from run_case;
    }
}

fn expect_contains(s: Suite&, haystack: const u8[:], needle: const u8[:]) {
    s.total_assertions += 1;
    if find(haystack, needle) < 0 {
        let start = begin_failure(s);
        format(s.log_buf, "expect_contains: `", haystack, "` does not contain `", needle, "`");
        end_failure(s, start);
        return from run_case;
    }
}

// --- 4. Compile-Time Struct Field Diffing (`const for`) ---------------------

fn expect_struct_eq<T>(s: Suite&, actual: T&, expected: T&, label: const u8[:] = "expect_struct_eq") {
    s.total_assertions += 1;
    var diff_count = 0;
    const for <N, A> in fields<T> {
        if !(actual.A == expected.A) {
            diff_count += 1;
        }
    }
    if diff_count > 0 {
        let start = begin_failure(s);
        format(s.log_buf, label, " (", diff_count, " field(s) differed):");
        const for <N, A> in fields<T> {
            if !(actual.A == expected.A) {
                format(s.log_buf, "\n           .", N, ": actual `", actual.A, "` != expected `", expected.A, "`");
            }
        }
        end_failure(s, start);
        return from run_case;
    }
}

// --- 5. Deterministic Property-Based Testing (`std::rng`) -------------------

inline fn property<F>(s: Suite&, prop_name: const u8[:], iterations: i64 = 100) {
    s.test(prop_name) {
        var r = rng { s: s.seed };
        for iter in iterations {
            F(r, iter);
            if s.current_failed {
                let start = begin_failure(s);
                format(s.log_buf, "property failed at iteration ", iter, " (reproduce with --seed ", s.seed, ")");
                end_failure(s, start);
                return from run_case;
            }
        }
    };
}

// --- 6. Zero-Overhead Auto-Calibrating Micro-Benchmarks ---------------------

inline fn bench<F>(s: Suite&, bench_name: const u8[:], min_time_ns: i64 = 5000000) {
    guard matches_filter(s, bench_name) else { return; }
    // Warmup
    F(0);
    var iters = 1;
    var elapsed = 0;
    while elapsed < min_time_ns && iters < 10000000 {
        iters *= 10;
        let t0 = clock_ns();
        for i in iters { F(i); }
        elapsed = clock_ns() - t0;
    }
    let ns_per_op = elapsed / max(1, iters);
    print("  ⏱ bench ", bench_name, ": ", iters, " iters, ", ns_per_op, " ns/op");
}

// --- 7. Suite Summary Reporter ----------------------------------------------

fn finish(s: Suite&) -> i32 {
    let total_ms = (clock_ns() - s.suite_start_ns) / 1000000;
    if s.tap_format {
        print("1..", s.passed + s.failed);
    } else {
        if s.failure_spans.len > 0 {
            print("\nFailures:");
            for span in s.failure_spans {
                write_stdout(s.log_buf[span.offset..span.offset + span.len]);
            }
        }
        print("\nSuite `", s.name, "`: ",
              s.passed, " passed, ",
              s.failed, " failed, ",
              s.skipped, " skipped, ",
              s.total_assertions, " assertions (", total_ms, " ms)");
    }
    return if s.failed == 0 { 0 } else { 1 };
}

// ============================================================================
// Demo Suite Exercising Every Feature
// ============================================================================

struct UserProfile {
    id: i64,
    email: const u8[:],
    role: const u8[:],
    active: bool,
}

fn main() {
    var s = new_suite("PromptNook Core & Router Spec");

    s.describe("Scalar & String Assertions") {
        s.test("equality, near, and substring assertions pass") {
            s.expect_eq(2 + 2, 4, "addition");
            s.expect_ne("admin", "viewer", "roles");
            s.expect_near(3.14159, 3.1416, 0.001, "pi approximation");
            s.expect_contains("PATCH /api/workspaces/ws_1", "workspaces");
        };

        s.test("demonstrates non-aborting failure + struct field diffing") {
            let actual = UserProfile { id: 10, email: "bob@nook.dev", role: "viewer", active: false };
            let expected = UserProfile { id: 10, email: "bob@nook.dev", role: "admin", active: true };
            // Soft check records failure and keeps going:
            s.check_eq(actual.role, "owner", "soft role check");
            // Hard struct diff pinpoints exact mismatched fields (.role and .active) and unwinds test:
            s.expect_struct_eq(actual, expected, "profile comparison");
            // Unreachable in this test, but the NEXT test in the suite still runs!
            s.expect_true(false, "should not be reached");
        };

        s.test("subsequent tests continue running after an earlier test failed") {
            s.expect_true(true);
            s.expect_eq("goosetest", "goosetest");
        };
    };

    s.describe("Property-Based & Benchmark Suite") {
        s.property("reversing an array twice yields the original array", 50) { r, iter =>
            var xs: i64[..16] = [];
            let len = r.rand_int(16);
            for i in len { xs.push(r.rand_int(1000)); }
            var copy_xs = xs;
            reverse(copy_xs[..]);
            reverse(copy_xs[..]);
            s.expect_eq(copy_xs[..], xs[..], "double reverse invariant");
        };

        s.bench("std::hash 24-byte key") { i =>
            let h = hash("workspaces/collaborators");
            assert(h != 0);
        };
    };

    let code = s.finish();
    print("Suite exit code (1 expected because of intentional demo failure): ", code);
}
