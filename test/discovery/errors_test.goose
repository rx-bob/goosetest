// Diagnostics preserve the offending path, configured budget, and native error number.
namespace errors_test;

import goosetest;

import src.discovery.errors;
import src.discovery.model;
import test_support.filesystem;

fn test_diagnostics(outer: goosetest::Test&) {
    filesystem_support::with_inventory() {
        inventory =>
        discovery::fail(inventory, discovery::Error.PathLimit, "src/a.goose", 0, 10);
        assert(discovery::error_text(inventory) == "src/a.goose: max_path_bytes exceeded (limit 10)");
    }
    filesystem_support::with_inventory() {
        inventory =>
        discovery::fail(inventory, discovery::Error.OpenDirectory, "src/locked", 13);
        let expected = "src/locked: cannot open directory without following links (errno 13)";
        assert(discovery::error_text(inventory) == expected);
    }
}
