// Literal stable-ID selection never depends on display labels or disabled state.
namespace selection_test;

import std;

import goosetest;
import src.discovery.declarations;
import src.discovery.manifest;
import src.discovery.model;
import src.discovery.selection;
import test_support.syntax;

fn test_kinds_and_ids(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        discovery::parse_file(manifest, "test/a_test.goose",
            str("namespace unit_test;\n// @DisplayName(\"friendly label\")\nfn test_alpha(t: goosetest::Test&) {}\n",
            "// @Disabled(\"later\")\nfn test_beta(t: goosetest::Test&) {}"), discovery::RootKind.Unit);
        discovery::parse_file(manifest, "integration/a_test.goose",
            "namespace integration_test;\nfn test_alpha(t: goosetest::Test&) {}", discovery::RootKind.Integration);
        discovery::finish_manifest(manifest);
        assert(discovery::manifest_status(manifest) == 0);
        assert(selection::count(manifest) == 3);
        assert(selection::count(manifest, selection::Options {
                suite: selection::Suite.Unit,
                ..
            }) == 2);
        assert(selection::count(manifest, selection::Options {
                suite: selection::Suite.Integration,
                ..
            }) == 1);
        assert(selection::count(manifest, selection::Options {
                filter: "test_alpha",
                ..
            }) == 2);
        assert(selection::count(manifest, selection::Options {
                filter: "test_beta",
                ..
            }) == 1);
        assert(selection::count(manifest, selection::Options {
                filter: "friendly label",
                ..
            }) == 0);
        assert(selection::count(manifest, selection::Options {
                filter: "unit_test::test_alpha",
                ..
            }) == 1);
        assert(selection::count(manifest, selection::Options {
                filter: "test_beta",
                suite: selection::Suite.Integration
            }) == 0);
        assert(manifest.cases.len == 3);
    }
}

fn test_literal_specials_and_empty(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        discovery::parse_file(manifest, "test/a[1]+_test.goose",
            "namespace unit_test;\nfn test_alpha(t: goosetest::Test&) {}", discovery::RootKind.Unit);
        discovery::finish_manifest(manifest);
        assert(discovery::manifest_status(manifest) == 0);
        assert(selection::count(manifest, selection::Options {
                filter: "[1]+",
                ..
            }) == 1);
        assert(selection::count(manifest, selection::Options {
                filter: "a.*",
                ..
            }) == 0);
        assert(selection::count(manifest, selection::Options {
                filter: "*",
                ..
            }) == 0);
        assert(selection::count(manifest, selection::Options {
                filter: "",
                ..
            }) == 1);
    }
    syntax_support::with_manifest() {
        manifest =>
        assert(selection::count(manifest) == 0);
    }
}

fn test_target_qualified_identity(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        discovery::set_target_name(manifest, "core");
        discovery::parse_file(manifest, "tests/core/path_test.goose",
            "namespace path_test;\nfn test_decode(t: goosetest::Test&) {}", discovery::RootKind.Unit);
        discovery::finish_manifest(manifest);
        assert(discovery::manifest_status(manifest) == 0);
        assert(discovery::manifest_text(manifest, manifest.cases[0].identity)
            == "core::tests/core/path_test.goose::path_test::test_decode");
        assert(selection::count(manifest, selection::Options {
                filter: "core::tests/core/",
                ..
            }) == 1);
        assert(selection::count(manifest, selection::Options {
                filter: "other::tests/core/",
                ..
            }) == 0);
    }
}
