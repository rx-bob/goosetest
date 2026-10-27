// Collision checks use stable IDs and suite namespaces, independent of labels or selection.
namespace catalog_test;

import goosetest;

import src.discovery.catalog;
import src.discovery.declarations;
import src.discovery.manifest;
import src.discovery.model;
import test_support.syntax;

fn test_duplicates(outer: goosetest::Test&) {
    syntax_support::expect_error("namespace x; fn test_x(t: goosetest::Test&) {} fn test_x(t: goosetest::Test&) {}",
        discovery::SyntaxIssue.DuplicateCase);
    syntax_support::with_manifest() {
        manifest =>
        discovery::parse_file(manifest, "test/a_test.goose", "namespace same;", discovery::RootKind.Unit);
        discovery::parse_file(manifest, "integration/b_test.goose", "namespace same;", discovery::RootKind.Integration);
        discovery::finish_manifest(manifest);
        assert(discovery::manifest_status(manifest) == 2);
        assert(manifest.error.issue == discovery::SyntaxIssue.SuiteCollision);
        assert(manifest.error_path == "integration/b_test.goose");
    }
}

fn test_labels_do_not_define_identity(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        let source = "namespace x;\n// @DisplayName(\"same\")\nfn test_one(t: goosetest::Test&) {}\n// @DisplayName(\"same\")\nfn test_two(t: goosetest::Test&) {}";
        syntax_support::parse(manifest, source);
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.cases.len == 2);
        assert(discovery::manifest_text(manifest, manifest.cases[0].identity)
            == "test/example_test.goose::x::test_one");
        assert(discovery::manifest_text(manifest, manifest.cases[1].identity)
            == "test/example_test.goose::x::test_two");
    }
}

fn test_empty_manifest(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        discovery::finish_manifest(manifest);
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.cases.len == 0);
    }
}

fn test_inventory_selection(outer: goosetest::Test&) {
    var files: discovery::SourceFile[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var error_path: u8[>..] = [];
    var inventory = discovery::new_inventory(files, paths, sources, error_path);
    add_file(inventory, "integration/flow_test.goose", "namespace flow; fn test_flow(t: goosetest::Test&) {}",
        discovery::RootKind.Integration);
    add_file(inventory, "src/code.goose", "this is not a test suite", discovery::RootKind.Source);
    add_file(inventory, "test/code_test.goose", "namespace code; fn test_code(t: goosetest::Test&) {}",
        discovery::RootKind.Unit);
    inventory.complete = true;
    syntax_support::with_manifest() {
        manifest =>
        discovery::discover(manifest, inventory);
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.suites.len == 2);
        assert(manifest.cases.len == 2);
        assert(manifest.suites[0].source_file == 0);
        assert(manifest.suites[1].source_file == 2);
        assert(manifest.suites[0].kind == discovery::RootKind.Integration);
        assert(manifest.suites[1].kind == discovery::RootKind.Unit);
    }
    inventory.complete = false;
    syntax_support::with_manifest() {
        manifest =>
        discovery::discover(manifest, inventory);
        assert(manifest.error.issue == discovery::SyntaxIssue.IncompleteInventory);
        assert(discovery::manifest_status(manifest) == 2);
    }
}

fn add_file(inventory: discovery::Inventory&, path: u8[:], source: u8[:], kind: discovery::RootKind) {
    let path_span = discovery::Span {
        offset: inventory.paths.len,
        length: path.len
    };
    let source_span = discovery::Span {
        offset: inventory.sources.len,
        length: source.len
    };
    inventory.paths.append(path);
    inventory.sources.append(source);
    inventory.files.push(discovery::SourceFile {
            path: path_span,
            source: source_span,
            kind: kind
        });
}

fn test_strict_suite_files(outer: goosetest::Test&) {
    for path in["test/helper.goose", "integration/helper.goose", "test/_test.goose"] {
        var files: discovery::SourceFile[>..] = [];
        var paths: u8[>..] = [];
        var sources: u8[>..] = [];
        var errors: u8[>..] = [];
        var inventory = discovery::new_inventory(files, paths, sources, errors);
        add_file(inventory, path, "namespace helper;", discovery::RootKind.Unit);
        inventory.complete = true;
        syntax_support::with_manifest() {
            manifest =>
            discovery::discover(manifest, inventory);
            assert(discovery::manifest_status(manifest) == 2);
            assert(manifest.error.issue == discovery::SyntaxIssue.BadTestFilename);
            assert(manifest.error_path == path);
        }
    }
}

fn test_disabled_suite_is_nonempty(outer: goosetest::Test&) {
    var files: discovery::SourceFile[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var errors: u8[>..] = [];
    var inventory = discovery::new_inventory(files, paths, sources, errors);
    add_file(inventory, "integration/disabled_test.goose",
        "namespace disabled;\n// @Disabled(\"pending\")\nfn test_pending(t: goosetest::Test&) {}",
        discovery::RootKind.Integration);
    inventory.complete = true;
    syntax_support::with_manifest() {
        manifest =>
        discovery::discover(manifest, inventory);
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.cases.len == 1 && manifest.cases[0].disabled);
    }
}
