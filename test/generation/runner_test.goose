// Generation is deterministic and rejects incomplete inputs or exhausted output budgets.
namespace runner_test;

import std;

import goosetest;
import src.discovery.manifest;
import src.discovery.selection;
import src.generation.model;
import src.generation.runner;
import test_support.generation;
import test_support.syntax;

fn test_deterministic_and_limits(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, "namespace sample; fn test_x(t: goosetest::Test&) {}");
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                first =>
                generation::generate(first, manifest, audit);
                assert(generation::status(first) == 0);
                assert(first.modules.len == 4);
                generation_support::with_output() {
                    second =>
                    generation::generate(second, manifest, audit);
                    assert(first.paths == second.paths);
                    assert(first.sources == second.sources);
                }
                let exact = generation::Limits {
                    max_files: first.modules.len,
                    max_source_bytes: first.sources.len,
                    max_path_bytes: first.paths.len
                };
                generation_support::with_output(exact) {
                    output =>
                    generation::generate(output, manifest, audit);
                    assert(generation::status(output) == 0);
                }
                for limit in 0..3 {
                    var below = exact;
                    if limit == 0 {
                        below.max_files -= 1;
                    }
                    if limit == 1 {
                        below.max_source_bytes -= 1;
                    }
                    if limit == 2 {
                        below.max_path_bytes -= 1;
                    }
                    generation_support::with_output(below) {
                        output =>
                        generation::generate(output, manifest, audit);
                        assert(generation::status(output) == 2);
                        assert(output.error.len > 0);
                        assert(output.sources.len <= below.max_source_bytes);
                    }
                }
            }
        }
    }
}

fn test_target_module_paths_and_identity(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        discovery::set_target_name(manifest, "core");
        syntax_support::parse(manifest, "namespace sample; fn test_x(t: goosetest::Test&) {}");
        assert(discovery::manifest_text(manifest, manifest.cases[0].identity)
            == "core::test/example_test.goose::sample::test_x");
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 0);
                assert(generation::module_path(output, output.modules[0]) == "core/case_0.goose");
                assert(generation::module_path(output, output.modules[1]) == "core/runner.goose");
                let case = generation::module_source(output, output.modules[0]);
                assert(find(case, "source_path() -> u8[>..]") >= 0);
                assert(find(case, "text.append(\"core::test/example_test.goose\")") >= 0);
                let runner = generation::module_source(output, output.modules[1]);
                assert(find(runner, "goosetest_generated.core.case_0") >= 0);
                assert(find(runner, "goosetest_generated.core.completion") >= 0);
                assert(find(runner, "goosetest_generated/core/completion") >= 0);
            }
        }
    }
}

fn test_incomplete(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 2);
                assert(output.modules.len == 0);
            }
            syntax_support::parse(manifest, "namespace x; fn test_x(t: goosetest::Test&) {}");
            audit.complete = false;
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 2);
                assert(output.modules.len == 0);
            }
        }
    }
}

fn test_filtered_calls_remain(outer: goosetest::Test&) {
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

fn test_only_disabled_selected(outer: goosetest::Test&) {
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

fn test_zero_selection_and_budget(outer: goosetest::Test&) {
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
                assert(generation::status(output) == 2);
                assert(output.modules.len == 0);
                assert(find(output.error[..], "selection matched no cases") >= 0);
            }
        }
    }
}
