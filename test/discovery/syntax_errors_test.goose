// Source diagnostics carry both line/column and the owned offending file path.
namespace syntax_errors_test;

import goosetest;

import src.discovery.manifest;
import src.discovery.model;
import test_support.syntax;

fn test_location_diagnostic(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, "namespace x;\r\n  recursive fn test_x(t: goosetest::Test&) {}");
        assert(discovery::manifest_status(manifest) == 2);
        assert(manifest.error.location.line == 2);
        assert(manifest.error.location.column == 13);
        let expected = "test/example_test.goose:2:13: unsupported test or hook declaration modifiers";
        assert(discovery::manifest_error_text(manifest) == expected);
    }
}
