// Per-case hooks follow signatures; unsupported suite lifecycle and unsafe names fail before emission.
namespace suites_test;

import std;

import goosetest.src.discovery.manifest;
import goosetest.src.generation.model;
import goosetest.src.generation.runner;
import goosetest.src.generation.validation;
import goosetest.test_support.generation;
import goosetest.test_support.syntax;

fn test_rejections() {
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

fn test_fixture_wrappers() {
    let source = """
namespace sample;
struct Fixture { value: i64 }
fn before_each(t: goosetest::Test&, f: Fixture&) {}
fn after_each(f: Fixture&) {}
fn test_fixture(t: goosetest::Test&, f: Fixture&) {}
fn test_plain(t: goosetest::Test&) {}
""";
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        assert(discovery::manifest_status(manifest) == 0);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 0);
                let fixture = generation::module_source(output, output.modules[0]);
                let plain = generation::module_source(output, output.modules[1]);
                assert(find(fixture, "goosetest::execute_fixture(t, identity)") >= 0);
                assert(find(fixture, "sample::Fixture {\n            ..\n        }") >= 0);
                assert(find(fixture, "goosetest::run_phase(t, goosetest::Phase.Setup)") >= 0);
                assert(find(fixture, "sample::before_each(t, fixture)") >= 0);
                assert(find(fixture, "sample::test_fixture(t, fixture)") >= 0);
                assert(find(fixture, "sample::after_each(fixture)") >= 0);
                assert(find(fixture, "if t.failures == 0 && !t.results.incomplete") >= 0);
                assert(find(fixture, "Phase.Cleanup") > find(fixture, "Phase.Body"));
                assert(find(plain, "goosetest::execute_case(t, identity)") >= 0);
                assert(find(plain, "sample::test_plain(t)") >= 0);
                assert(find(plain, "Fixture") < 0 && find(plain, "before_each") < 0);
                assert(find(plain, "after_each") < 0 && find(plain, "execute_fixture") < 0);
            }
        }
    }
}

fn test_fixture_without_hooks() {
    let source = "namespace sample; struct Fixture {} fn test_fixture(t: goosetest::Test&, f: Fixture&) {}";
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 0);
                let fixture = generation::module_source(output, output.modules[0]);
                assert(find(fixture, "sample::Fixture") >= 0);
                assert(find(fixture, "Phase.Body") >= 0);
                assert(find(fixture, "Phase.Setup") < 0);
                assert(find(fixture, "Phase.Cleanup") < 0);
            }
        }
    }
}

fn test_fixture_identifier_bounds() {
    var namespace_name: u8[>..] = [];
    var function_name: u8[>..] = [];
    for index in 0..48 {
        namespace_name.push('a');
    }
    function_name.append("test_");
    for index in 0..43 {
        function_name.push('b');
    }
    let source = str("namespace ", namespace_name, "; struct Fixture { value: i64 } fn ", function_name,
        "(t: goosetest::Test&, f: Fixture&) {}");
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 0);
                let generated = generation::module_source(output, output.modules[0]);
                var column: i64 = 0;
                for byte in generated {
                    if byte == '\n' {
                        column = 0;
                    } else {
                        column += 1;
                        assert(column <= 120);
                    }
                }
                assert(find(generated, "                    t, fixture\n                );") >= 0);
            }
        }
    }
}
