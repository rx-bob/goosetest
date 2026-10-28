// Adapter probes verify bounded reads, missing-entry distinctions, and no-follow opens.
namespace filesystem_test;

import os;
import std;

import goosetest;
import src.platform.filesystem;
import test_support.filesystem;
import test_support.selfhost;

fn test_adapter(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let root = filesystem_support::project(parent, "adapter");
    filesystem_support::write(root, "data", "abc");
    filesystem_support::write(root, "empty", "");
    assert(filesystem_support::symlink("src", str(root, "/linked_directory")) == 0);
    assert(filesystem_support::symlink("data", str(root, "/linked_file")) == 0);
    let fd = filesystem::open_project(root);
    assert(fd >= 0);
    assert(filesystem::kind(fd, "src") == filesystem::DIRECTORY);
    assert(filesystem::kind(fd, "data") == filesystem::FILE);
    assert(filesystem::kind(fd, "linked_file") == filesystem::SYMLINK);
    assert(filesystem::missing(filesystem::kind(fd, "absent")) != 0);
    assert(filesystem::missing(filesystem::kind(-1, "absent")) == 0);
    assert(filesystem::open_directory(fd, "linked_directory") < 0);
    var exact: u8[>..] = [];
    assert(filesystem::read(fd, "data", exact, 3) == 0);
    assert(exact == "abc");
    var limited: u8[>..] = [];
    assert(filesystem::read(fd, "data", limited, 2) == filesystem::READ_LIMIT);
    assert(limited.len <= 2);
    assert(filesystem::read(fd, "empty", limited, 0) == 0);
    assert(filesystem::read(fd, "linked_file", limited, 3) < 0);
    assert(filesystem::read(fd, "src", limited, 3) < 0);
    assert(filesystem::read(fd, "../data", limited, 3) < 0);
    assert(filesystem::read(fd, "data\0ignored", limited, 3) < 0);
    assert(filesystem::next(0, limited) < 0);
    let handle = filesystem::open_directory(fd, "src");
    assert(handle > 0);
    assert(filesystem::next(handle, limited) == 0);
    assert(filesystem::close_directory(handle) == 0);
    assert(filesystem::close_project(fd) == 0);
}

fn test_replacement(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let root = filesystem_support::project(parent, "replacement");
    filesystem_support::write(root, "source.goose", "original");
    filesystem_support::write(root, "outside", "must not be read");
    let fd = filesystem::open_project(root);
    assert(fd >= 0);
    assert(filesystem::kind(fd, "source.goose") == filesystem::FILE);
    assert(delete_file(str(root, "/source.goose")));
    assert(filesystem_support::symlink("outside", str(root, "/source.goose")) == 0);
    var bytes: u8[>..] = [];
    assert(filesystem::read(fd, "source.goose", bytes, 100) < 0);
    assert(bytes.len == 0);
    assert(filesystem::kind(fd, "src") == filesystem::DIRECTORY);
    assert(delete_dir(str(root, "/src")));
    assert(filesystem_support::symlink("test", str(root, "/src")) == 0);
    assert(filesystem::open_directory(fd, "src") < 0);
    assert(filesystem::close_project(fd) == 0);
}
