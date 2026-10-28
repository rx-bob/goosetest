// Compiler-contract fixture only; the shipping runtime is implemented in E1.S2.
namespace goosetest;

import bridges;
import src.execution;

struct Test {
    failed: bool = false,
    reached: bool = false,
}

fn assert_eq<T>(t: Test&, expected: T, actual: T, message: u8[:] = "") {
    if expected != actual {
        t.failed = true;
        return from goosetest::run_case;
    }
}
