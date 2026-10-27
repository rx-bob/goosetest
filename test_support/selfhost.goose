// Owned scratch space and native process fixture for the generated self-host suite.
namespace selfhost_support;

import goosetest;
import os;
import std;
import src.platform.process;

extern "gt_selfhost_prepare" fn native_prepare() -> i32;
extern "gt_selfhost_root"fn native_root(path: u8[:]) -> i64;
extern "gt_selfhost_cleanup"fn native_cleanup() -> i32;

fn root() -> u8[>..] {
    var bytes: u8[>..] = [];
    for index in 0..4096 {
        bytes.push(0);
    }
    let length = native_root(bytes);
    assert(length > 0 && length < bytes.len);
    var path: u8[>..] = [];
    path.append(bytes[0..length]);
    return path;
}

fn prepare() -> bool {
    if native_prepare() != 0 {
        return false;
    }
    let directory = root();
    let source = str(directory, "/process-child.c");
    let output = child();
    if !write_file(source, embed_file("../integration/fixtures/process/child.c")) {
        return false;
    }
    let result = process::run(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", source, "-o", output],
        directory, process::Limits {
            deadline_ms: 120000,
            grace_ms: 1000
        });
    return result.outcome == process::Outcome.Exited && result.exit_code == 0 && result.cleanup_error == 0;
}

fn scratch(outer: goosetest::Test&) -> u8[>..] {
    assert(outer.current_case >= 0);
    let path = str(root(), "/case_", outer.current_case);
    assert(make_dir(path));
    return path;
}

fn child() -> u8[>..] {
    return str(root(), "/process-child");
}

fn cleanup() -> bool {
    return native_cleanup() == 0;
}
