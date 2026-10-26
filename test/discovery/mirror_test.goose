// Audit correspondence independently of syntax and preserve every mismatch.
namespace mirror_test;

import std;

import goosetest.src.discovery.mirror;
import goosetest.src.discovery.model;
import goosetest.test_support.filesystem;
import goosetest.test_support.mirror;

fn test_order_and_prefixes() {
    filesystem_support::with_inventory() {
        inventory =>
        // Opposite full-path ordering after adding _test must not break matches.
        for name in["a", "a0", "a_b", "a_test", "nested/a", "nested/a0"] {
            mirror_support::add(inventory, str("src/", name, ".goose"), discovery::RootKind.Source);
        }
        for name in["nested/a0", "a_test", "a_b", "a0", "a", "nested/a"] {
            mirror_support::add(inventory, str("test/", name, "_test.goose"), discovery::RootKind.Unit);
        }
        mirror_support::add(inventory, "integration/cross_test.goose", discovery::RootKind.Integration);
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 0);
            assert(audit.matched == 6 && audit.integration_files == 1);
            assert(audit.records.len == 6);
            for record in audit.records {
                assert(record.kind == discovery::MirrorKind.Matched);
                assert(discovery::mirror_key(inventory, record.source_index)
                    == discovery::mirror_key(inventory, record.test_index));
            }
        }
    }
}

fn test_rename() {
    filesystem_support::with_inventory() {
        inventory =>
        mirror_support::add(inventory, "src/new.goose", discovery::RootKind.Source);
        mirror_support::add(inventory, "test/old_test.goose", discovery::RootKind.Unit);
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 2);
            assert(audit.complete && audit.missing == 1 && audit.orphaned == 1);
            assert(audit.records.len == 2);
            assert(discovery::mirror_record_text(inventory, audit.records[0])
                == "MISSING TEST  src/new.goose\n              expected test/new_test.goose");
            assert(discovery::mirror_record_text(inventory, audit.records[1])
                == "ORPHAN TEST  test/old_test.goose\n             expected src/old.goose");
        }
    }
}

fn test_bad_names() {
    filesystem_support::with_inventory() {
        inventory =>
        mirror_support::add(inventory, "test/helper.goose", discovery::RootKind.Unit);
        mirror_support::add(inventory, "test/nested/_test.goose", discovery::RootKind.Unit);
        mirror_support::add(inventory, "integration/helper.goose", discovery::RootKind.Integration);
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 2);
            assert(audit.bad_names == 3 && audit.records.len == 3);
            for record,
            index in audit.records {
                assert(record.kind == discovery::MirrorKind.BadTestName);
                assert(record.test_index == index);
            }
        }
    }
}

fn test_empty_and_incomplete() {
    filesystem_support::with_inventory() {
        inventory =>
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 2);
            assert( !audit.complete && audit.records.len == 0);
        }
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 0);
            assert(audit.records.len == 0);
        }
    }
}

fn test_large_audit() {
    filesystem_support::with_inventory() {
        inventory =>
        for index in 0..350 {
            mirror_support::add(inventory, str("src/m", index, ".goose"), discovery::RootKind.Source);
            mirror_support::add(inventory, str("test/m", index, "_test.goose"), discovery::RootKind.Unit);
        }
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 0);
            assert(audit.matched == 350 && audit.records.len == 350);
            for record in audit.records {
                assert(record.test_index == record.source_index + 1);
            }
        }
    }
}
