// Discovery success cannot turn a truncated generator output into a publishable run.
namespace limits_integration_test;

import std;

import goosetest;
import src.discovery.manifest;
import src.generation.artifacts;
import src.generation.model;
import src.generation.runner;
import test_support.generation;
import test_support.syntax;

fn test_generation_limit_preserves_failure(outer: goosetest::Test&) {
    syntax_support::with_manifest() {
        manifest =>
        syntax_support::parse(manifest,
            "namespace bounded; fn test_first(t: goosetest::Test&) {} fn test_second(t: goosetest::Test&) {}");
        assert(discovery::manifest_status(manifest) == 0);
        assert(manifest.cases.len == 2);
        generation_support::with_audit() {
            audit =>
            generation_support::with_output(generation::Limits {
                    max_files: 1,
                    ..
                }) {
                output =>
                generation::generate(output, manifest, audit);
                assert(generation::status(output) == 2);
                assert(!output.complete);
                assert(output.modules.len == 1);
                assert(find(output.error[..], "max_files exceeded") >= 0);
                assert(artifacts::publish(-1, output) == -1);
                assert(manifest.cases.len == 2);
            }
        }
    }
}
