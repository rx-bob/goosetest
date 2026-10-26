// Owns manifest arenas for independent bootstrap syntax checks.
namespace syntax_support;

import src.discovery.catalog;
import src.discovery.declarations;
import src.discovery.manifest;
import src.discovery.model;

fn with_manifest<F>(limits: discovery::SyntaxLimits = discovery::SyntaxLimits {
    }) {
    var suites: discovery::Suite[>..] = [];
    var cases: discovery::Case[>..] = [];
    var text: u8[>..] = [];
    var error_path: u8[>..] = [];
    var manifest = discovery::new_manifest(suites, cases, text, error_path, limits);
    F(manifest);
}

fn parse(manifest: discovery::Manifest&, source: u8[:]) {
    discovery::parse_file(manifest, "test/example_test.goose", source, discovery::RootKind.Unit);
    discovery::finish_manifest(manifest);
}

fn expect_error(source: u8[:], issue: discovery::SyntaxIssue, line: i64 = 0) {
    with_manifest() {
        manifest =>
        parse(manifest, source);
        assert(discovery::manifest_status(manifest) == 2);
        assert(manifest.error.issue == issue);
        assert(manifest.error_path == "test/example_test.goose");
        assert(manifest.error.location.line > 0);
        if line > 0 {
            assert(manifest.error.location.line == line);
        }
    }
}
