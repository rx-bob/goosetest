// One case owns its counters and diagnostic bytes until the next execution.
namespace goosetest;

struct Test {
    assertions: i64 = 0,
    failures: i64 = 0,
    diagnostics: u8[>..] = [],
}

fn reset(t: Test&) {
    t.assertions = 0;
    t.failures = 0;
    t.diagnostics.clear();
}

// Read after run_case returns; hard failures bypass the rest of its body.
fn case_status(t: Test&) -> i32 {
    return if t.failures > 0 {
        1
    } else {
        0
    };
}
