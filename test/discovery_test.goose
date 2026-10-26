// Bootstrap filesystem suite; parent owns and removes the supplied temporary root.
import goosetest from "..";
import goosetest.test_support.filesystem;

import os;
import std;

import discovery.errors_test;
import discovery.files_test;
import discovery.model_test;
import discovery.paths_test;
import platform.filesystem_test;

fn main() {
    assert(arg_count() == 2);
    assert(filesystem_support::unprivileged() != 0);
    var root: u8[>..] = [];
    arg(1, root);
    assert( !is_dir(root));
    assert( !file_exists(root));
    assert(make_dir(root));
    let descriptors = filesystem_support::fd_count();
    paths_test::test_segments();
    model_test::test_invalid_limits();
    model_test::test_status();
    errors_test::test_diagnostics();
    files_test::test_directory_read_error();
    files_test::test_empty_and_optional(root);
    files_test::test_owned_content(root);
    files_test::test_missing_roots(root);
    files_test::test_invalid_paths(root);
    files_test::test_links(root);
    files_test::test_unreadable(root);
    files_test::test_limits(root);
    files_test::test_large_trees(root);
    filesystem_test::test_adapter(root);
    filesystem_test::test_replacement(root);
    assert(filesystem_support::fd_count() == descriptors);
    print("discovery tests passed");
}
