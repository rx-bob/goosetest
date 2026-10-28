// Disabled calls remain compiler-visible while runtime paths only record skips.
namespace suite_hooks_test;

import std;

import goosetest;
import src.discovery.manifest;
import src.generation.model;
import src.generation.runner;
import test_support.generation;
import test_support.syntax;

fn test_all_disabled_wrappers(outer: goosetest::Test&) {
    let source = """
namespace sample;
struct Fixture { value: i64 }
fn before_all(t: goosetest::Test&) {}
fn after_all(t: goosetest::Test&) {}
fn before_each(t: goosetest::Test&, f: Fixture&) {}
fn after_each(t: goosetest::Test&, f: Fixture&) {}
// @DisplayName("same label")
// @Disabled("pending")
fn test_fixture(t: goosetest::Test&, f: Fixture&) {}
// @DisplayName("same label")
// @Disabled("another reason")
fn test_plain(t: goosetest::Test&) {}
""";
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 0);
                let first = generation::module_source(output, output.modules[0]);
                let last = generation::module_source(output, output.modules[1]);
                assert(find(first, "if false {\n        before_suite(t);") >= 0);
                assert(find(last, "if false {\n        after_suite(t);") >= 0);
                assert(find(first, "t.suite_active = true") < 0);
                assert(find(first, "if false {\n        run_disabled(t, identity);") >= 0);
                assert(find(first, "fn run_disabled") >= 0);
                assert(find(first, "sample::Fixture") > find(first, "fn run_disabled"));
                assert(find(first, "sample::before_each(t, fixture)") >= 0);
                assert(find(first, "sample::after_each(t, fixture)") >= 0);
                assert(find(last, "sample::Fixture") < 0);
                assert(find(first, "suite setup failed") < 0);
                assert(find(first, "source_reason()") >= 0);
            }
        }
    }
}

fn test_mixed_disabled_reason(outer: goosetest::Test&) {
    let source = """
namespace sample;
fn before_all(t: goosetest::Test&) {}
// @Disabled("own reason")
fn test_disabled(t: goosetest::Test&) {}
fn test_enabled(t: goosetest::Test&) {}
""";
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 0);
                let disabled = generation::module_source(output, output.modules[0]);
                let enabled = generation::module_source(output, output.modules[1]);
                assert(find(disabled, "t.suite_ready = before_suite(t)") >= 0);
                assert(find(disabled, "suite setup failed") < 0);
                assert(find(enabled, "suite setup failed") >= 0);
                let suite = manifest.suites[0];
                var expected = suite.path.length + suite.namespace_name.length + "before_all".len;
                for entry in manifest.cases {
                    expected += suite.path.length + suite.namespace_name.length + entry.name.length;
                }
                expected += "own reason".len + "suite setup failed".len;
                assert(generation::metadata_size(manifest) == expected);
            }
        }
    }
}

fn test_reason_bound(outer: goosetest::Test&) {
    for length in 1024..1026 {
        var reason: u8[>..] = [];
        for index in 0..length {
            reason.push('a');
        }
        syntax_support::with_manifest() {
            manifest =>
            syntax_support::parse(manifest, str("namespace sample;\n// @Disabled(\"", reason,
                "\")\nfn test_disabled(t: goosetest::Test&) {}"));
            generation_support::with_audit() {
                audit =>
                generation_support::with_output() {
                    output =>
                    generation::generate(output, manifest, audit);
                    if length == 1024 {
                        assert(generation::status(output) == 0);
                    } else {
                        assert(generation::status(output) == 2);
                        assert(output.modules.len == 0);
                        assert(find(output.error[..], "disabled reason") >= 0);
                    }
                }
            }
        }
    }
}
