// Incomplete generation cannot claim files; complete publication retains exact module bytes.
namespace artifacts_test;

import os;
import std;

import goosetest;
import src.generation.artifacts;
import src.generation.model;
import src.platform.filesystem;
import src.platform.staging;
import test_support.generation;
import test_support.selfhost;

fn test_incomplete_output_rejected(outer: goosetest::Test&) {
    generation_support::with_output() {
        output =>
        generation::add_module(output, "runner.goose", "namespace generated;\n");
        assert(artifacts::publish( - 1, output) == - 1);
    }
}

fn test_publication_replaces_owned_modules(outer: goosetest::Test&) {
    let root = selfhost_support::scratch(outer);
    assert(write_file(str(root, "/goosetest_root.goose"), "// owned root\n"));
    let fd = staging::create(root);
    assert(fd >= 0);
    generation_support::with_output() {
        output =>
        generation::add_module(output, "runner.goose", "namespace entry;\n");
        generation::add_module(output, "suite_0.goose", "namespace suite;\n");
        output.complete = true;
        assert(artifacts::publish(fd, output) == 0);
    }
    var text: u8[>..] = [];
    assert(filesystem::read(fd, "suite_0.goose", text, 100) == 0);
    assert(text == "namespace suite;\n");
    generation_support::with_output() {
        output =>
        generation::add_module(output, "runner.goose", "namespace replacement;\n");
        output.complete = true;
        assert(artifacts::publish(fd, output) == 0);
    }
    assert(filesystem::missing(filesystem::kind(fd, "suite_0.goose")) != 0);
    text.clear();
    assert(filesystem::read(fd, "runner.goose", text, 100) == 0);
    assert(text == "namespace replacement;\n");
    assert(filesystem::close_project(fd) == 0);
}
