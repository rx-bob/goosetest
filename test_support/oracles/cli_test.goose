// Independent child-process oracle: parent passes captured bytes and actual exit status.

import os;

fn main() {
    assert(arg_count() == 5);
    var actual_path: u8[>..] = [];
    var expected_path: u8[>..] = [];
    var actual_status: u8[>..] = [];
    var expected_status: u8[>..] = [];
    arg(1, actual_path);
    arg(2, expected_path);
    arg(3, actual_status);
    arg(4, expected_status);
    var actual: u8[>..] = [];
    var expected: u8[>..] = [];
    assert(read_file(actual_path, actual));
    assert(read_file(expected_path, expected));
    assert(actual_status == expected_status);
    assert(actual == expected);
}
