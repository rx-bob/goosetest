import std;
import os;

// ============================================================================
// goosetest/contained: Panic & Abort Isolation via `thread_spawn_contained`
// ============================================================================
// In Goose (Spec §22), `assert(false)`, `abort("...")`, bounds-check failures,
// and `--debug` overflow checks terminate the program on the main thread.
// However, when run inside `thread_spawn_contained(worker, args...)`, any
// abort/assert/panic terminates ONLY that worker and delivers the exact
// runtime diagnostic + file:line to `thread_wait(id, why) -> bool`!
//
// This gives `goosetest` two capabilities rare in systems languages without fork():
//   1. `expect_abort(s, name, id, substr)` — assert that code panics/aborts
//      with a specific diagnostic message.
//   2. `test_isolated(s, name, id)` — sandbox untrusted/crashy tests so an
//      unexpected `assert()` or out-of-bounds panic is reported as a `[FAIL]`
//      without bringing down the test runner!

struct FailureSpan {
    offset: i64,
    len: i64,
}

struct ContainedSuite {
    name: const u8[:],
    passed: i64 = 0,
    failed: i64 = 0,
    failure_spans: FailureSpan[..64] = [],
    log_buf: u8[>..],
}

fn new_contained_suite(name: const u8[:]) -> ContainedSuite {
    return ContainedSuite { name: name, log_buf: [], .. };
}

fn record_contained_failure(s: ContainedSuite&, test_name: const u8[:], detail: const u8[:]) {
    let start = s.log_buf.len;
    format(s.log_buf, "  [FAIL] ", test_name, "\n         ", detail, "\n");
    if s.failure_spans.len < s.failure_spans.cap {
        s.failure_spans.push(FailureSpan { offset: start, len: s.log_buf.len - start });
    }
}

// 1. Assert that a contained worker aborts and its diagnostic contains `expected_substr`
fn expect_abort(s: ContainedSuite&, test_name: const u8[:], worker_id: i64, expected_substr: const u8[:]) {
    var why: u8[>..] = [];
    let ok = thread_wait(worker_id, why);
    if ok {
        s.failed += 1;
        print("  ✗ ", test_name, " (expected abort, but worker succeeded)");
        record_contained_failure(s, test_name, "expected worker to abort, but it returned normally");
        return;
    }
    if find(why, expected_substr) < 0 {
        s.failed += 1;
        print("  ✗ ", test_name, " (aborted with wrong diagnostic)");
        var msg: u8[>..] = [];
        format(msg, "expected abort containing `", expected_substr, "`, got: `", trim(why), "`");
        record_contained_failure(s, test_name, msg);
        return;
    }
    s.passed += 1;
    print("  ✓ ", test_name, " (caught expected abort: `", trim(why), "`)");
}

// 2. Run a test inside a contained worker so an unexpected panic/abort is caught cleanly
fn test_isolated(s: ContainedSuite&, test_name: const u8[:], worker_id: i64) {
    var why: u8[>..] = [];
    let ok = thread_wait(worker_id, why);
    if !ok {
        s.failed += 1;
        print("  ✗ ", test_name, " (caught unexpected panic/abort)");
        var msg: u8[>..] = [];
        format(msg, "worker panicked: ", trim(why));
        record_contained_failure(s, test_name, msg);
        return;
    }
    s.passed += 1;
    print("  ✓ ", test_name);
}

fn finish(s: ContainedSuite&) -> i32 {
    if s.failure_spans.len > 0 {
        print("\nCaptured Contained Failures:");
        for span in s.failure_spans {
            write_stdout(s.log_buf[span.offset..span.offset + span.len]);
        }
    }
    print("\nContained Suite `", s.name, "`: ", s.passed, " passed, ", s.failed, " failed");
    return if s.failed == 0 { 0 } else { 1 };
}

// --- Example Workers Under Test ---------------------------------------------

thread_fn worker_divide_by_zero_guard(divisor: i64) {
    if divisor == 0 {
        abort("division by zero in router rate limiter");
    }
}

thread_fn worker_out_of_bounds_bug(idx: i64) {
    let items = [10, 20, 30];
    let v = items[idx]; // Panics when idx >= 3!
    assert(v > 0);
}

fn main() {
    var s = new_contained_suite("Contained Panic & Abort Isolation Spec");

    // 1. Verify expected `abort(...)` is caught and message is matched:
    s.expect_abort(
        "rate limiter aborts on zero window",
        thread_spawn_contained(worker_divide_by_zero_guard, 0),
        "division by zero in router rate limiter"
    );

    // 2. Verify expected out-of-bounds slice/index panic is caught:
    s.expect_abort(
        "bounds check catches out-of-range index",
        thread_spawn_contained(worker_out_of_bounds_bug, 99),
        "out of bounds"
    );

    // 3. Verify an isolated test that succeeds passes normally:
    s.test_isolated(
        "valid index succeeds in isolated worker",
        thread_spawn_contained(worker_out_of_bounds_bug, 1)
    );

    // 4. Verify an isolated test that hits an unexpected bug is caught WITHOUT crashing main:
    s.test_isolated(
        "unexpected index panic is caught and logged as test failure",
        thread_spawn_contained(worker_out_of_bounds_bug, 5)
    );

    let code = s.finish();
    print("Contained suite finished cleanly without crashing process (exit code ", code, ")");
}
