// Bootstrap ABI/result tests; parent builds and owns the purpose-built child.
import goosetest from "..";

import os;
import std;

import platform.process_test;

fn main() {
    assert(arg_count() == 3);
    var child: u8[>..] = [];
    var cwd: u8[>..] = [];
    arg(1, child);
    arg(2, cwd);
    process_test::test_exits(child, cwd);
    process_test::test_launch_and_signal(child, cwd);
    process_test::test_invalid();
    process_test::test_bounds(child, cwd);
    print("process unit tests passed");
}
