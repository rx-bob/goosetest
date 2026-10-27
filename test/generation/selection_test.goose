// Selection changes execution paths, never the discovered compile graph.
namespace selection_test;

import std;

import goosetest.src.discovery.manifest;
import goosetest.src.discovery.selection;
import goosetest.src.generation.model;
import goosetest.src.generation.runner;
import goosetest.test_support.generation;
import goosetest.test_support.syntax;

fn test_filtered_calls_remain() {
    let source = """
namespace sample;
struct Fixture { value: i64 }
fn before_all(t: goosetest::Test&) {}
fn after_all(t: goosetest::Test&) {}
fn before_each(t: goosetest::Test&, f: Fixture&) {}
fn after_each(t: goosetest::Test&, f: Fixture&) {}
fn test_first(t: goosetest::Test&, f: Fixture&) {}
fn test_selected(t: goosetest::Test&) {}
""";
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit, selection::Options {
                        filter: "test_selected",
                        ..
                    }, true);
                assert(generation::status(output) == 0);
                let first = generation::module_source(output, output.modules[0]);
                let selected = generation::module_source(output, output.modules[1]);
                assert(find(first, "if false {\n        run_unselected(t);") >= 0);
                assert(find(first, "goosetest::record_filtered(t.results)") >= 0);
                assert(find(first, "sample::Fixture") > find(first, "fn run_unselected"));
                assert(find(first, "sample::before_each(t, fixture)") >= 0);
                assert(find(first, "sample::after_each(t, fixture)") >= 0);
                assert(find(first, "!t.results.fail_fast_stop") >= 0);
                assert(find(selected, "goosetest::not_run_case(t.results, identity, \"fail-fast\")") >= 0);
                assert(find(selected, "if t.suite_active {\n        after_suite(t);") >= 0);
                let runner = generation::module_source(output, output.modules[3]);
                assert(find(runner, "results.fail_fast = true") >= 0);
                assert(find(runner, "report(results, 1)") >= 0);
            }
        }
    }
}

fn test_only_disabled_selected() {
    let source = """
namespace sample;
fn before_all(t: goosetest::Test&) {}
fn after_all(t: goosetest::Test&) {}
fn test_unselected(t: goosetest::Test&) {}
// @Disabled("pending")
fn test_disabled(t: goosetest::Test&) {}
""";
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, source);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit, selection::Options {
                        filter: "test_disabled",
                        ..
                    });
                assert(generation::status(output) == 0);
                let first = generation::module_source(output, output.modules[0]);
                let last = generation::module_source(output, output.modules[1]);
                assert(find(first, "if false {\n        before_suite(t);") >= 0);
                assert(find(last, "if false {\n        after_suite(t);") >= 0);
                assert(find(last, "goosetest::skip_case(t.results, identity, reason)") >= 0);
                assert(find(last, "goosetest::not_run_case") < 0);
                assert(find(last, "suite setup failed") < 0);
            }
        }
    }
}

fn test_zero_selection_and_budget() {
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, "namespace sample; fn test_a(t: goosetest::Test&) {}");
        assert(generation::metadata_size(manifest, true) == generation::metadata_size(manifest) + "fail-fast".len);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit, selection::Options {
                        filter: "absent",
                        ..
                    });
                assert(generation::status(output) == 2 && output.modules.len == 0);
                assert(find(output.error[..], "selection matched no cases") >= 0);
            }
        }
    }
}
