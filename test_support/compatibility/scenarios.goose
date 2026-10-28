// Runtime checks for the pinned compiler contract.
namespace compatibility_test;

import.users.alpha;
import.users.beta;
import goosetest;
import goosetest.src.execution;

fn test_bridge_recovery() {
    var failed = goosetest::Test {
    };
    goosetest::run_case(failed) {
        alpha_test::test_hard_stop(failed);
        failed.reached = true;
    }
    assert(failed.failed);
    assert(!failed.reached);

    var passed = goosetest::Test {
    };
    goosetest::run_case(passed) {
        beta_test::test_pass(passed);
    }
    assert(!passed.failed);
    assert(passed.reached);
}

fn test_nested_boundary() {
    var outer = goosetest::Test {
    };
    var inner = goosetest::Test {
    };
    goosetest::run_case(outer) {
        goosetest::run_case(inner) {
            inner.assert_eq(0, 1);
            inner.reached = true;
        }
        outer.reached = true;
    }
    assert(inner.failed);
    assert(!inner.reached);
    assert(outer.reached);
    assert(!outer.failed);
}

fn first_byte(bytes: u8[:]) -> u8 {
    assert(bytes.len > 0);
    return bytes[0];
}

fn test_storage() {
    var bytes: u8[>..] = [];
    let first .= bytes.push('a');
    let initial = bytes[..];
    for i in 0..256 {
        bytes.push('b');
    }
    first = 'c';
    assert(bytes.len == 257);
    assert(bytes[0] == 'c');
    assert(initial.len == 1);
    assert(first_byte(initial) == 'c');
    assert(first_byte("constant") == 'c');
    assert(first_byte(bytes) == 'c');
}
