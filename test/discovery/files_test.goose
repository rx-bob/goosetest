// Small trees verify roots, owned paths/content, ignored helpers, and explicit errors.
namespace files_test;

import goosetest;

import src.discovery.files;
import src.discovery.model;
import src.discovery.paths;
import test_support.filesystem;
import test_support.selfhost;

import os;
import std;

fn test_empty_and_optional(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let root = filesystem_support::project(parent, "empty");
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, root);
        assert(discovery::status(inventory) == 0);
        assert(inventory.files.len == 0);
        assert(inventory.visited_entries == 2);
    }
    filesystem_support::directory(root, "integration");
    filesystem_support::directory(root, "test_support");
    filesystem_support::directory(root, "goosetest_generated");
    filesystem_support::write(root, "integration/flow_test.goose", "// flow");
    assert(filesystem_support::symlink("missing", str(root, "/test_support/link")) == 0);
    assert(filesystem_support::symlink("missing", str(root, "/goosetest_generated/link")) == 0);
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, root);
        assert(discovery::status(inventory) == 0);
        assert(inventory.files.len == 1);
        assert(inventory.files[0].kind == discovery::RootKind.Integration);
        assert(discovery::path_text(inventory, inventory.files[0].path) == "integration/flow_test.goose");
    }
}

fn test_owned_content(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let root = filesystem_support::project(parent, "owned");
    filesystem_support::directory(root, "src/nested");
    filesystem_support::write(root, "src/nested/first.goose", "// first");
    filesystem_support::write(root, "test/first_test.goose", "// second");
    filesystem_support::write(root, "src/README.txt", "ignored");
    filesystem_support::write(root, "test/invalid.goose.data", "ignored");
    filesystem_support::with_inventory() {
        inventory =>
        scan_temporary_path(inventory, root);
        assert(discovery::status(inventory) == 0);
        assert(inventory.files.len == 2);
        assert(inventory.files[0].kind == discovery::RootKind.Source);
        assert(inventory.files[1].kind == discovery::RootKind.Unit);
        assert(discovery::path_text(inventory, inventory.files[0].path) == "src/nested/first.goose");
        assert(discovery::source_text(inventory, inventory.files[0]) == "// first");
        assert(discovery::source_text(inventory, inventory.files[1]) == "// second");
    }
}

fn scan_temporary_path(inventory: discovery::Inventory&, root: u8[:]) {
    let path = str(root, "/");
    discovery::scan(inventory, path);
}

fn test_missing_roots(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let root = str(parent, "/missing");
    assert(make_dir(root));
    expect_error(root, discovery::Error.MissingRoot, "src");
    filesystem_support::directory(root, "src");
    expect_error(root, discovery::Error.MissingRoot, "test");
    filesystem_support::write(root, "test", "not a directory");
    expect_error(root, discovery::Error.RootNotDirectory, "test");
}

fn test_invalid_paths(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let names: const u8[:][5] = ["bad-name.goose", "if.goose", "line\nbreak.goose", ".goose", "a\\b.goose"];
    for name,
    index in names {
        let root = filesystem_support::project(parent, str("invalid_", index));
        filesystem_support::write(root, str("src/", name), "");
        expect_error(root, discovery::Error.InvalidImport, str("src/", name));
    }
    let root = filesystem_support::project(parent, "invalid_directory");
    filesystem_support::directory(root, "src/bad-name");
    expect_error(root, discovery::Error.InvalidImport, "src/bad-name");
}

fn test_links(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let root = filesystem_support::project(parent, "cycle");
    assert(filesystem_support::symlink("../src", str(root, "/src/cycle")) == 0);
    expect_error(root, discovery::Error.Symlink, "src/cycle");
    let dangling = filesystem_support::project(parent, "dangling");
    assert(filesystem_support::symlink("missing", str(dangling, "/integration")) == 0);
    expect_error(dangling, discovery::Error.Symlink, "integration");
    let file = filesystem_support::project(parent, "file_link");
    filesystem_support::write(file, "outside.goose", "outside");
    assert(filesystem_support::symlink("../outside.goose", str(file, "/src/linked.goose")) == 0);
    expect_error(file, discovery::Error.Symlink, "src/linked.goose");
}

fn test_unreadable(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    assert(filesystem_support::unprivileged() != 0);
    let root = filesystem_support::project(parent, "unreadable_file");
    filesystem_support::write(root, "src/locked.goose", "denied");
    let file = str(root, "/src/locked.goose");
    assert(filesystem_support::chmod(file, 0) == 0);
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, root);
        assert(filesystem_support::chmod(file, 384) == 0);
        assert(inventory.error == discovery::Error.ReadSource);
        assert(inventory.error_path == "src/locked.goose");
        assert(inventory.system_error > 0);
        assert(discovery::status(inventory) == 2);
    }
    let directory = filesystem_support::project(parent, "unreadable_directory");
    filesystem_support::directory(directory, "src/locked");
    let locked = str(directory, "/src/locked");
    assert(filesystem_support::chmod(locked, 0) == 0);
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, directory);
        assert(filesystem_support::chmod(locked, 448) == 0);
        assert(inventory.error == discovery::Error.OpenDirectory);
        assert(inventory.system_error > 0);
        assert(discovery::status(inventory) == 2);
    }
}

fn expect_error(root: u8[:], expected: discovery::Error, path: u8[:]) {
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, root);
        assert(discovery::status(inventory) == 2);
        assert( !inventory.complete);
        assert(inventory.error == expected);
        assert(inventory.error_path == path);
    }
}

fn test_directory_read_error(outer: goosetest::Test&) {
    filesystem_support::with_inventory() {
        inventory =>
        let path = discovery::record_path(inventory, "src", 0);
        var stack: discovery::DirectoryFrame[>..<] = [];
        // Invalid native handle deterministically exercises the iterator error branch.
        stack.push(discovery::DirectoryFrame {
                handle: 0,
                path: path,
                depth: 0
            });
        discovery::walk(inventory, stack, discovery::RootKind.Source);
        discovery::close_stack(inventory, stack);
        assert(discovery::status(inventory) == 2);
        assert(inventory.error == discovery::Error.ListDirectory);
        assert(inventory.error_path == "src");
        assert(inventory.system_error > 0);
        assert(stack.len == 0);
    }
}

fn test_limits(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let empty = filesystem_support::project(parent, "exact_empty");
    let exact = discovery::Limits {
        max_entries: 2,
        max_depth: 0,
        max_path_bytes: 4,
        max_path_storage_bytes: 7,
        max_file_bytes: 0,
        max_source_bytes: 0,
    };
    verify(empty, exact, discovery::Error.None, "");
    verify(empty, discovery::Limits {
            max_entries: 1,
            ..
        }, discovery::Error.EntryLimit, "test");
    verify(empty, discovery::Limits {
            max_path_bytes: 3,
            ..
        }, discovery::Error.PathLimit, "test");
    verify(empty, discovery::Limits {
            max_path_storage_bytes: 6,
            ..
        }, discovery::Error.PathStorageLimit, "test");
    let nested = filesystem_support::project(parent, "exact_depth");
    filesystem_support::directory(nested, "src/d");
    verify(nested, discovery::Limits {
            max_depth: 1,
            ..
        }, discovery::Error.None, "");
    verify(nested, discovery::Limits {
            max_depth: 0,
            ..
        }, discovery::Error.DepthLimit, "src/d");
    let source = filesystem_support::project(parent, "exact_source");
    filesystem_support::write(source, "src/a.goose", "12345");
    verify(source, discovery::Limits {
            max_file_bytes: 5,
            ..
        }, discovery::Error.None, "");
    verify(source, discovery::Limits {
            max_file_bytes: 4,
            ..
        }, discovery::Error.FileSizeLimit, "src/a.goose");
    verify(source, discovery::Limits {
            max_source_bytes: 5,
            ..
        }, discovery::Error.None, "");
    verify(source, discovery::Limits {
            max_source_bytes: 4,
            ..
        }, discovery::Error.SourceSizeLimit, "src/a.goose");
    verify(source, discovery::Limits {
            max_path_bytes: 11,
            ..
        }, discovery::Error.None, "");
    verify(source, discovery::Limits {
            max_path_bytes: 10,
            ..
        }, discovery::Error.PathLimit, "src/a.goose");
    verify(source, discovery::Limits {
            max_path_storage_bytes: 18,
            ..
        }, discovery::Error.None, "");
    verify(source, discovery::Limits {
            max_path_storage_bytes: 17,
            ..
        }, discovery::Error.PathStorageLimit, "test");
}

fn verify(root: u8[:], limits: discovery::Limits, expected: discovery::Error, path: u8[:]) {
    let before = filesystem_support::fd_count();
    filesystem_support::with_inventory(limits) {
        inventory =>
        discovery::scan(inventory, root);
        assert(inventory.error == expected);
        assert(inventory.error_path == path);
        if expected == discovery::Error.None {
            assert(discovery::status(inventory) == 0);
        } else {
            assert(discovery::status(inventory) == 2);
            assert(inventory.limit >= 0);
        }
        assert(inventory.paths.len <= limits.max_path_storage_bytes);
        assert(inventory.sources.len <= limits.max_source_bytes);
        assert(inventory.visited_entries <= limits.max_entries);
    }
    assert(filesystem_support::fd_count() == before);
}

fn test_large_trees(outer: goosetest::Test&) {
    let parent = selfhost_support::scratch(outer);
    let forward = make_large(parent, "forward", false);
    let reverse = make_large(parent, "reverse", true);
    verify_order(forward);
    verify_order(reverse);
}

fn make_large(parent: u8[:], name: u8[:], reverse: bool) -> u8[>..] {
    let root = filesystem_support::project(parent, name);
    for step in 0..70 {
        let index = if reverse {
            69 - step
        } else {
            step
        };
        let directory = str("src/d_", index + 1000);
        filesystem_support::directory(root, directory);
        filesystem_support::write(root, str(directory, "/x.goose"), str("// nested ", index));
    }
    for step in 0..140 {
        let index = if reverse {
            139 - step
        } else {
            step
        };
        filesystem_support::write(root, str("src/f_", index + 1000, ".goose"), str("// source ", index));
        filesystem_support::write(root, str("test/f_", index + 1000, "_test.goose"), str("// test ", index));
    }
    return root;
}

fn verify_order(root: u8[:]) {
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, root);
        assert(discovery::status(inventory) == 0);
        assert(inventory.files.len == 350);
        assert(inventory.visited_entries == 422);
        for index in 0..70 {
            let file = inventory.files[index];
            assert(discovery::path_text(inventory, file.path) == str("src/d_", index + 1000, "/x.goose"));
            assert(discovery::source_text(inventory, file) == str("// nested ", index));
        }
        for index in 0..140 {
            let source = inventory.files[index + 70];
            let unit = inventory.files[index + 210];
            assert(discovery::path_text(inventory, source.path) == str("src/f_", index + 1000, ".goose"));
            assert(discovery::path_text(inventory, unit.path) == str("test/f_", index + 1000, "_test.goose"));
            assert(discovery::source_text(inventory, source) == str("// source ", index));
            assert(discovery::source_text(inventory, unit) == str("// test ", index));
        }
    }
}
