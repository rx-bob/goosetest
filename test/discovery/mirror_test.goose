// Audit correspondence independently of syntax and preserve every mismatch.
namespace mirror_test;

import std;

import goosetest;
import src.discovery.mirror;
import src.discovery.model;
import test_support.filesystem;
import test_support.mirror;

fn test_order_and_prefixes(outer: goosetest::Test&) {
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
            assert(audit.matched == 6);
            assert(audit.integration_files == 1);
            assert(audit.records.len == 6);
            for record in audit.records {
                assert(record.kind == discovery::MirrorKind.Matched);
                assert(discovery::mirror_key(inventory, record.source_index)
                    == discovery::mirror_key(inventory, record.test_index));
            }
        }
    }
}

fn test_rename(outer: goosetest::Test&) {
    filesystem_support::with_inventory() {
        inventory =>
        mirror_support::add(inventory, "src/new.goose", discovery::RootKind.Source);
        mirror_support::add(inventory, "test/old_test.goose", discovery::RootKind.Unit);
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 2);
            assert(audit.complete);
            assert(audit.missing == 1);
            assert(audit.orphaned == 1);
            assert(audit.records.len == 2);
            assert(discovery::mirror_record_text(inventory, audit.records[0])
                == "MISSING TEST  src/new.goose\n              expected test/new_test.goose");
            assert(discovery::mirror_record_text(inventory, audit.records[1])
                == "ORPHAN TEST  test/old_test.goose\n             expected src/old.goose");
        }
    }
}

fn test_bad_names(outer: goosetest::Test&) {
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
            assert(audit.bad_names == 3);
            assert(audit.records.len == 3);
            for record,
            index in audit.records {
                assert(record.kind == discovery::MirrorKind.BadTestName);
                assert(record.test_index == index);
            }
        }
    }
}

fn test_empty_and_incomplete(outer: goosetest::Test&) {
    filesystem_support::with_inventory() {
        inventory =>
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 2);
            assert(!audit.complete);
            assert(audit.records.len == 0);
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

fn test_large_audit(outer: goosetest::Test&) {
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
            assert(audit.matched == 350);
            assert(audit.records.len == 350);
            for record in audit.records {
                assert(record.test_index == record.source_index + 1);
            }
        }
    }
}

fn test_configured_pair_roots_and_relative_stems(outer: goosetest::Test&) {
    filesystem_support::with_inventory() {
        inventory =>
        inventory.configured = true;
        let source = add_root(inventory, "src/request", discovery::RootKind.Source, 0);
        let tests = add_root(inventory, "tests/deep", discovery::RootKind.Unit, 0);
        add_root_file(inventory, "src/request/a.goose", discovery::RootKind.Source, source, 0);
        add_root_file(inventory, "src/request/a0.goose", discovery::RootKind.Source, source, 0);
        add_root_file(inventory, "tests/deep/a_test.goose", discovery::RootKind.Unit, tests, 0);
        add_root_file(inventory, "tests/deep/a0_test.goose", discovery::RootKind.Unit, tests, 0);
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 0);
            assert(audit.matched == 2);
        }
    }
}

fn test_configured_pairs_do_not_cross_match(outer: goosetest::Test&) {
    filesystem_support::with_inventory() {
        inventory =>
        inventory.configured = true;
        let source_left = add_root(inventory, "src/left", discovery::RootKind.Source, 0);
        add_root(inventory, "tests/left", discovery::RootKind.Unit, 0);
        add_root(inventory, "src/right", discovery::RootKind.Source, 1);
        let tests_right = add_root(inventory, "tests/right", discovery::RootKind.Unit, 1);
        add_root_file(inventory, "src/left/same.goose", discovery::RootKind.Source, source_left, 0);
        add_root_file(inventory, "tests/right/same_test.goose", discovery::RootKind.Unit, tests_right, 1);
        inventory.complete = true;
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 2);
            assert(audit.missing == 1);
            assert(audit.orphaned == 1);
            assert(discovery::mirror_record_text(inventory, audit.records[0])
                == "MISSING TEST  src/left/same.goose\n              expected tests/left/same_test.goose");
            assert(discovery::mirror_record_text(inventory, audit.records[1])
                == "ORPHAN TEST  tests/right/same_test.goose\n             expected src/right/same.goose");
        }
    }
}

fn add_root(inventory: discovery::Inventory&, path: u8[:], kind: discovery::RootKind, pair: i64) -> i64 {
    let span = discovery::Span {
        offset: inventory.paths.len,
        length: path.len
    };
    inventory.paths.append(path);
    let index = inventory.roots.len;
    inventory.roots.push(discovery::RootRecord {
            path: span,
            kind: kind,
            target: 0,
            pair: pair
        });
    return index;
}

fn add_root_file(
    inventory: discovery::Inventory&, path: u8[:], kind: discovery::RootKind, root: i64, pair: i64
) {
    let path_span = discovery::Span {
        offset: inventory.paths.len,
        length: path.len
    };
    inventory.paths.append(path);
    inventory.files.push(discovery::SourceFile {
            path: path_span,
            source: discovery::Span {
                offset: 0,
                length: 0
            },
            kind: kind,
            root: root,
            pair: pair,
        });
}
