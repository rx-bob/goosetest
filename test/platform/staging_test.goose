// Prepared ownership constrains writes and completion accepts only an exact status record.
namespace staging_test;

import os;
import std;

import goosetest;
import src.platform.filesystem;
import src.platform.staging;
import test_support.selfhost;

fn test_claimed_names(outer: goosetest::Test&) {
    let root = selfhost_support::scratch(outer);
    assert(write_file(str(root, "/goosetest_root.goose"), "// owned root\n"));
    let fd = staging::create(root);
    assert(fd >= 0);
    assert(staging::prepare(fd, "runner.goose\n") == 0);
    assert(staging::write(fd, "unclaimed.goose", "unowned") != 0);
    assert(staging::write(fd, "../escape.goose", "escape") != 0);
    assert(staging::write(fd, "runner.goose", "namespace generated;\n") == 0);
    assert(staging::finish(fd, "runner.goose\n") == 0);
    assert(filesystem::close_project(fd) == 0);
    assert(!file_exists(str(root, "/escape.goose")));
}

fn test_completion_bytes(outer: goosetest::Test&) {
    let root = selfhost_support::scratch(outer);
    assert(write_file(str(root, "/goosetest_root.goose"), "// owned root\n"));
    let fd = staging::create(root);
    assert(fd >= 0);
    assert(staging::completion(fd, 0) != 0);
    let completion = str(root, "/goosetest_generated/completion");
    assert(write_file(completion, "0\n"));
    assert(staging::completion(fd, 0) == 0);
    assert(staging::completion(fd, 1) != 0);
    assert(write_file(completion, "0\nextra"));
    assert(staging::completion(fd, 0) != 0);
    assert(filesystem::close_project(fd) == 0);
}
