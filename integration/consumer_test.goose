// The adoption templates enter the same audited manifest and generator as real projects.
namespace consumer_integration_test;

import std;

import goosetest;
import src.discovery.files;
import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.model;
import src.generation.model;
import src.generation.runner;
import test_support.filesystem;
import test_support.generation;
import test_support.mirror;
import test_support.selfhost;
import test_support.syntax;

fn test_pretty_goose_adoption_manifest(outer: goosetest::Test&) {
    let scratch = selfhost_support::scratch(outer);
    let project = filesystem_support::project(scratch, "consumer");
    materialize(project);
    filesystem_support::with_inventory() {
        inventory =>
        discovery::scan(inventory, project);
        outer.assert_eq(0, discovery::status(inventory));
        mirror_support::with_audit() {
            audit =>
            syntax_support::with_manifest() {
                manifest =>
                discovery::inspect_project(audit, manifest, inventory);
                outer.assert_eq(0, discovery::project_status(audit, manifest));
                outer.assert_eq(2, audit.matched);
                outer.assert_eq(1, audit.integration_files);
                verify_manifest(outer, manifest);
                verify_generation(outer, manifest, audit);
            }
        }
    }
}

fn materialize(project: u8[:]) {
    filesystem_support::directory(project, "integration");
    filesystem_support::directory(project, "test_support");
    filesystem_support::write(project, "src/lexer.goose",
        embed_file("fixtures/pretty_goose/consumer/src/lexer.goose.data"));
    filesystem_support::write(project, "src/formatter.goose",
        embed_file("fixtures/pretty_goose/consumer/src/formatter.goose.data"));
    filesystem_support::write(project, "test/lexer_test.goose",
        embed_file("fixtures/pretty_goose/consumer/test/lexer_test.goose.data"));
    filesystem_support::write(project, "test/formatter_test.goose",
        embed_file("fixtures/pretty_goose/consumer/test/formatter_test.goose.data"));
    filesystem_support::write(project, "integration/pipeline_test.goose",
        embed_file("fixtures/pretty_goose/consumer/integration/pipeline_test.goose.data"));
    filesystem_support::write(project, "test_support/contracts.goose",
        embed_file("fixtures/pretty_goose/consumer/test_support/contracts.goose.data"));
}

fn verify_manifest(outer: goosetest::Test&, manifest: discovery::Manifest&) {
    outer.assert_eq(3, manifest.suites.len);
    outer.assert_eq(3, manifest.cases.len);
    const expected: const u8[:][3] = [
        "integration/pipeline_test.goose::consumer_pipeline_test::test_format_and_lex",
        "test/formatter_test.goose::consumer_formatter_test::test_statement_blocks",
        "test/lexer_test.goose::consumer_lexer_test::test_literal_preservation"
    ];
    for entry,
    index in manifest.cases {
        outer.assert_eq(expected[index], discovery::manifest_text(manifest, entry.identity));
        outer.assert_false(entry.disabled);
    }
}

fn verify_generation(outer: goosetest::Test&, manifest: discovery::Manifest&, audit: discovery::MirrorAudit&) {
    generation_support::with_output() {
        output =>
        generation::generate(output, manifest, audit);
        outer.assert_eq(0, generation::status(output));
        const expected_imports: const u8[:][3] = [
            "import integration.pipeline_test;", "import test.formatter_test;", "import test.lexer_test;"
        ];
        const expected_calls: const u8[:][3] = [
            "consumer_pipeline_test::test_format_and_lex(t)",
            "consumer_formatter_test::test_statement_blocks(t)",
            "consumer_lexer_test::test_literal_preservation(t)"
        ];
        for index in 0..3 {
            let wrapper = generation::module_source(output, output.modules[index]);
            outer.assert_contains(expected_imports[index], wrapper);
            outer.assert_contains(expected_calls[index], wrapper);
        }
    }
}
