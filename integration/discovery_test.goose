// Filesystem-to-manifest checks use parent-owned disposable projects and builtin assertions.
namespace discovery_integration_test;

import os;
import std;

import goosetest;
import src.discovery.files;
import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.model;
import test_support.filesystem;
import test_support.mirror;
import test_support.selfhost;
import test_support.syntax;

fn test_project(outer: goosetest::Test&) {
    let root = selfhost_support::scratch(outer);
    let project = filesystem_support::project(root, "valid");
    for name in["a", "a0"] {
        filesystem_support::write(project, str("src/", name, ".goose"), "namespace production;");
        filesystem_support::write(project, str("test/", name, "_test.goose"),
            str("namespace ", name, "; fn test_ok(t: goosetest::Test&) {}"));
    }
    filesystem_support::directory(project, "integration");
    filesystem_support::write(project, "integration/cross_test.goose",
        "namespace cross; import src.a; import src.a0; fn test_cross(t: goosetest::Test&) {}");
    for name in["test_support", "goosetest_generated", "native"] {
        filesystem_support::directory(project, name);
        filesystem_support::write(project, str(name, "/ignored.goose"), "deliberately invalid");
    }
    filesystem_support::write(project, "main.goose", "root entry outside audit");
    filesystem_support::write(project, "facade.goose", "root facade outside audit");
    check_valid(project);
    // A selectable valid case cannot conceal a different module's missing mirror.
    filesystem_support::write(project, "src/hidden.goose", "namespace hidden;");
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, project);
        mirror_support::with_audit() {
            audit =>
            syntax_support::with_manifest() {
                manifest =>
                discovery::inspect_project(audit, manifest, inventory);
                assert(discovery::project_status(audit, manifest) == 2);
                assert(audit.matched == 2);
                assert(audit.missing == 1);
                assert(manifest.cases.len == 0);
                assert(!manifest.complete);
            }
        }
    }
}

fn check_valid(project: u8[:]) {
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, project);
        mirror_support::with_audit() {
            audit =>
            syntax_support::with_manifest() {
                manifest =>
                discovery::inspect_project(audit, manifest, inventory);
                assert(discovery::project_status(audit, manifest) == 0);
                assert(audit.matched == 2);
                assert(audit.integration_files == 1);
                assert(manifest.cases.len == 3);
                assert(manifest.suites.len == 3);
                assert(discovery::manifest_text(manifest, manifest.cases[0].identity)
                    == "integration/cross_test.goose::cross::test_cross");
            }
        }
    }
}

fn test_empty_suites(outer: goosetest::Test&) {
    let root = selfhost_support::scratch(outer);
    for kind in["unit", "integration"] {
        let project = filesystem_support::project(root, kind);
        var path = str("test/empty_test.goose");
        if kind == "unit" {
            filesystem_support::write(project, "src/empty.goose", "");
        } else {
            filesystem_support::directory(project, "integration");
            path = str("integration/empty_test.goose");
        }
        filesystem_support::write(project, path, "namespace empty; fn helper() {}");
        filesystem_support::with_inventory() {
            inventory =>
            discovery::scan(inventory, project);
            mirror_support::with_audit() {
                audit =>
                syntax_support::with_manifest() {
                    manifest =>
                    discovery::inspect_project(audit, manifest, inventory);
                    assert(discovery::project_status(audit, manifest) == 2);
                    assert(manifest.error.issue == discovery::SyntaxIssue.EmptySuite);
                    assert(manifest.error_path == path);
                }
            }
        }
    }
}

fn test_original_poc(outer: goosetest::Test&) {
    let root = selfhost_support::scratch(outer);
    let project = filesystem_support::project(root, "original_poc");
    filesystem_support::directory(project, "src/workspaces");
    filesystem_support::write(project, "src/workspaces/archive.goose", "namespace archive;");
    for name in["first", "second"] {
        filesystem_support::write(project, str("src/", name, ".goose"), "namespace production;");
        filesystem_support::write(project, str("test/", name, "_test.goose"), "namespace tests;");
    }
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, project);
        assert(discovery::status(inventory) == 0);
        mirror_support::with_audit() {
            audit =>
            discovery::audit_mirrors(audit, inventory);
            assert(discovery::mirror_status(audit) == 2);
            assert(audit.matched == 2);
            assert(audit.missing == 1);
            assert(audit.orphaned == 0);
            var found = false;
            for record in audit.records {
                if record.kind == discovery::MirrorKind.MissingTest {
                    let expected = str("MISSING TEST  src/workspaces/archive.goose\n",
                        "              expected test/workspaces/archive_test.goose");
                    assert(discovery::mirror_record_text(inventory, record) == expected);
                    found = true;
                }
            }
            assert(found);
        }
    }
}

fn test_no_cases(outer: goosetest::Test&) {
    let root = selfhost_support::scratch(outer);
    let project = filesystem_support::project(root, "no_cases");
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, project);
        mirror_support::with_audit() {
            audit =>
            syntax_support::with_manifest() {
                manifest =>
                discovery::inspect_project(audit, manifest, inventory);
                assert(discovery::mirror_status(audit) == 0);
                assert(discovery::project_status(audit, manifest) == 2);
                assert(manifest.error.issue == discovery::SyntaxIssue.NoCases);
            }
        }
    }
}
