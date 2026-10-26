// Ordinary authoring survives multiline syntax and lexical decoys; malformed declarations fail explicitly.
namespace declarations_test;

import goosetest.src.discovery.catalog;
import goosetest.src.discovery.declarations;
import goosetest.src.discovery.manifest;
import goosetest.src.discovery.model;
import goosetest.test_support.syntax;

import std;

fn test_authoring() {
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, embed_file("../../integration/fixtures/syntax/authoring.goose.data"));
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.suites.len == 1);
        assert(manifest.cases.len == 2);
        let first = manifest.cases[0];
        let second = manifest.cases[1];
        assert(first.location.line == 14);
        assert(second.location.line == 26);
        assert(first.uses_fixture);
        assert( !second.uses_fixture);
        assert(discovery::manifest_text(manifest, first.identity)
            == "test/example_test.goose::sample_test::test_fixture");
        assert(discovery::manifest_text(manifest, first.display_name) == "quoted \"label\" A\t\\");
        assert(discovery::manifest_text(manifest, first.disabled_reason) == "pending\nclock");
        assert(first.disabled);
        let suite = manifest.suites[0];
        assert(suite.before_each.present);
        assert( !suite.before_each.uses_context);
        assert(suite.after_each.uses_context);
        assert(suite.after_each.uses_fixture);
        assert(suite.before_all.present);
        assert( !suite.before_all.uses_context);
        assert(suite.after_all.uses_context);
    }
}

fn test_namespace_and_fixture_errors() {
    syntax_support::expect_error("", discovery::SyntaxIssue.MissingNamespace, 1);
    syntax_support::expect_error("fn test_x(t: goosetest::Test&) {}", discovery::SyntaxIssue.NamespaceOrder, 1);
    syntax_support::expect_error("namespace x; namespace x;", discovery::SyntaxIssue.DuplicateNamespace, 1);
    syntax_support::expect_error("fn helper() {} namespace x;", discovery::SyntaxIssue.NamespaceOrder, 1);
    syntax_support::expect_error("namespace x; struct Fixture {} struct Fixture {}",
        discovery::SyntaxIssue.DuplicateFixture);
    syntax_support::expect_error("namespace x; struct Fixture<T> {}", discovery::SyntaxIssue.FixtureShape);
    syntax_support::expect_error("namespace x; fn test_x(t: goosetest::Test&, f: Fixture&) {}",
        discovery::SyntaxIssue.MissingFixture);
    syntax_support::expect_error("namespace x; fn before_each(f: Fixture&) {}", discovery::SyntaxIssue.MissingFixture);
    syntax_support::expect_error("namespace x; inline", discovery::SyntaxIssue.DanglingModifier);
}

fn test_late_fixture_and_crlf() {
    syntax_support::with_manifest() {
        manifest =>
        let source = "import goosetest;\r\nnamespace late;\r\ninline\r\nfn test_x(\r\n t: goosetest::Test&,\r\n f: Fixture&,\r\n) {}\r\nstruct Fixture {}";
        syntax_support::parse(manifest, source);
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.cases[0].location.line == 4);
        assert(manifest.cases[0].location.column == 1);
        assert(manifest.suites[0].has_fixture);
    }
}

fn test_owned_names() {
    syntax_support::with_manifest() {
        manifest =>
        parse_temporary(manifest);
        discovery::finish_manifest(manifest);
        assert(discovery::manifest_status(manifest) == 0);
        assert(discovery::manifest_text(manifest, manifest.cases[0].identity)
            == "integration/owned_test.goose::owned::test_x");
        assert(discovery::manifest_text(manifest, manifest.cases[0].display_name) == "temporary");
    }
}

fn parse_temporary(manifest: discovery::Manifest&) {
    let source = str("namespace owned;\n", "// @DisplayName(\"temporary\")\nfn test_x(t: goosetest::Test&) {}");
    let path = str("integration/", "owned_test.goose");
    discovery::parse_file(manifest, path, source, discovery::RootKind.Integration);
}
