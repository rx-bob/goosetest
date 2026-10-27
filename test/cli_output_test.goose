// Listing bytes stay deterministic even when metadata contains decoded controls.
namespace cli_output_test;

import goosetest;
import src.cli_output;
import src.discovery.manifest;
import test_support.syntax;

fn test_output(outer: goosetest::Test&) {
    assert(cli_output::escaped("why\n\t\0\r\\\x7F") == "why\\x0A\\x09\\x00\\x0D\\\\\\x7F");
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest,
            "namespace sample;\n// @Disabled(\"pending\")\nfn test_x(t: goosetest::Test&) {}");
        assert(discovery::manifest_status(manifest) == 0);
        assert(cli_output::case_line(manifest, manifest.cases[0])
            == "unit  test/example_test.goose::sample::test_x  (test/example_test.goose:3:1)\n");
        assert(cli_output::case_summary(manifest) == "1 discovered cases: 0 executable, 1 disabled\n");
    }
}
