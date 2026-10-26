// Bootstrap full layout validation; parent owns temporary fixture cleanup.
import goosetest from "..";
import goosetest.integration.discovery_test;

import os;
import std;

import discovery.mirror_test;

fn main() {
    assert(arg_count() == 3);
    var root: u8[>..] = [];
    var poc: u8[>..] = [];
    arg(1, root);
    arg(2, poc);
    assert( !is_dir(root) && !file_exists(root));
    assert(make_dir(root));
    mirror_test::test_order_and_prefixes();
    mirror_test::test_rename();
    mirror_test::test_bad_names();
    mirror_test::test_empty_and_incomplete();
    mirror_test::test_large_audit();
    discovery_integration_test::test_project(root);
    discovery_integration_test::test_no_cases(root);
    discovery_integration_test::test_empty_suites(root);
    discovery_integration_test::test_original_poc(poc);
    print("mirror tests passed");
}
