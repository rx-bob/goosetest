// Generation is deterministic and rejects incomplete inputs or exhausted output budgets.
namespace runner_test;

import goosetest.src.discovery.manifest;
import goosetest.src.generation.model;
import goosetest.src.generation.runner;
import goosetest.test_support.generation;
import goosetest.test_support.syntax;

fn test_deterministic_and_limits() {
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest, "namespace sample; fn test_x(t: goosetest::Test&) {}");
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                first =>
                generation::generate(first, manifest, audit);
                assert(generation::status(first) == 0 && first.modules.len == 4);
                generation_support::with_output() {
                    second =>
                    generation::generate(second, manifest, audit);
                    assert(first.paths == second.paths && first.sources == second.sources);
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
                        assert(generation::status(output) == 2 && output.error.len > 0);
                        assert(output.sources.len <= below.max_source_bytes);
                    }
                }
            }
        }
    }
}

fn test_incomplete() {
    syntax_support::with_manifest() {
        manifest =>
        generation_support::with_audit() {
            audit =>
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 2 && output.modules.len == 0);
            }
            syntax_support::parse(manifest, "namespace x; fn test_x(t: goosetest::Test&) {}");
            audit.complete = false;
            generation_support::with_output() {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 2 && output.modules.len == 0);
            }
        }
    }
}
