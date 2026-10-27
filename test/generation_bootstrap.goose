// Independent source-generation checks use builtin assertions, without native code.
import goosetest from "..";

import std;

import generation.disabled_test;
import generation.literals_test;
import generation.model_test;
import generation.runner_test;
import generation.suites_test;
import generation.validation_test;

fn main() {
    generation_model_test::test_invalid_limits();
    validation_test::test_paths();
    validation_test::test_path_bounds();
    literals_test::test_bytes();
    literals_test::test_function_bounds();
    runner_test::test_deterministic_and_limits();
    runner_test::test_incomplete();
    suites_test::test_rejections();
    disabled_test::test_all_disabled_wrappers();
    disabled_test::test_mixed_disabled_reason();
    disabled_test::test_reason_bound();
    suites_test::test_fixture_wrappers();
    suites_test::test_suite_hook_wrappers();
    suites_test::test_fixture_without_hooks();
    suites_test::test_fixture_identifier_bounds();
    suites_test::test_label_limit();
    print("generation unit tests passed");
}
