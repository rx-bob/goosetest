// Inventory status rejects unfinished and invalid scans before any filesystem work.
namespace model_test;

import goosetest;

import src.discovery.files;
import src.discovery.model;
import test_support.filesystem;

fn test_invalid_limits(outer: goosetest::Test&) {
    let limits: discovery::Limits[6] = [
        discovery::Limits {
            max_entries: - 1,
            ..
        }, discovery::Limits {
            max_depth: - 1,
            ..
        },
        discovery::Limits {
            max_path_bytes: - 1,
            ..
        }, discovery::Limits {
            max_path_storage_bytes: - 1,
            ..
        },
        discovery::Limits {
            max_file_bytes: - 1,
            ..
        }, discovery::Limits {
            max_source_bytes: - 1,
            ..
        },
    ];
    for limit in limits {
        filesystem_support::with_inventory(limit) {
            inventory =>
            discovery::scan(inventory, "does-not-exist");
            assert(inventory.error == discovery::Error.InvalidLimits);
            assert(discovery::status(inventory) == 2);
            assert(inventory.files.len == 0);
        }
    }
}

fn test_status(outer: goosetest::Test&) {
    filesystem_support::with_inventory() {
        inventory =>
        assert(discovery::status(inventory) == 2);
        discovery::fail(inventory, discovery::Error.PathLimit, "src/a.goose", 0, 10);
        discovery::fail(inventory, discovery::Error.ReadSource, "other", 5);
        assert(inventory.error_path == "src/a.goose");
        assert(inventory.error == discovery::Error.PathLimit);
        assert(inventory.limit == 10);
    }
}
