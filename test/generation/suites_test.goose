// Unsupported lifecycle and unsafe identifier channels fail before module emission.
namespace suites_test;

import std;

import goosetest.src.discovery.manifest;
import goosetest.src.generation.model;
import goosetest.src.generation.runner;
import goosetest.src.generation.validation;
import goosetest.test_support.generation;
import goosetest.test_support.syntax;

fn test_rejections() {
    reject("namespace x; struct Fixture {} fn test_x(t: goosetest::Test&, f: Fixture&) {}");
    reject("namespace x; fn before_all() {} fn test_x(t: goosetest::Test&) {}");
    reject("namespace x;\n// @Disabled(\"pending\")\nfn test_x(t: goosetest::Test&) {}");
    reject("namespace goosetest_generated; fn test_x(t: goosetest::Test&) {}");
    reject("namespace goosetest_generated_extra; fn test_x(t: goosetest::Test&) {}");
    assert( !generation::identifier("x; injected"));
    assert( !generation::identifier("namespace"));
    assert(generation::identifier("test_valid"));
}

fn reject(source: u8[:]) {
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        assert(discovery::manifest_status(manifest) == 0);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 2);
                assert(output.modules.len == 0 && output.error.len > 0);
            }
        }
    }
}

fn test_label_limit() {
    var label: u8[>..] = [];
    for index in 0..1025 {
        label.push('a');
    }
    reject(str("namespace x;\n// @DisplayName(\"", label, "\")\nfn test_x(t: goosetest::Test&) {}"));
}
