// Test fixtures use an externally owned temporary root, cleaned by the invoking parent.
namespace filesystem_support;

import os;
import std;

import src.discovery.model;

extern "gt_test_symlink" fn symlink(target: const u8[:], path: const u8[:]) -> i32;
extern "gt_test_chmod"fn chmod(path: const u8[:], mode: i32) -> i32;
extern "gt_test_unprivileged"fn unprivileged() -> i32;
extern "gt_test_fd_count"fn fd_count() -> i64;

fn project(parent: u8[:], name: u8[:]) -> u8[>..] {
    let root = str(parent, "/", name);
    assert(make_dir(root));
    assert(make_dir(str(root, "/src")));
    assert(make_dir(str(root, "/test")));
    return root;
}

fn directory(root: u8[:], relative: u8[:]) {
    assert(make_dir(str(root, "/", relative)));
}

fn write(root: u8[:], relative: u8[:], content: u8[:]) {
    assert(write_file(str(root, "/", relative), content));
}

fn with_inventory<F>(limits: discovery::Limits = discovery::Limits {
    }) {
    var files: discovery::SourceFile[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var error_path: u8[>..] = [];
    var inventory = discovery::new_inventory(files, paths, sources, error_path, limits);
    F(inventory);
}
