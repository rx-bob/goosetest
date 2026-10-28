// Compiler profile argv has an exact, independently testable shape.
namespace build_test;

import goosetest;
import src.arguments;
import src.execution.build;

fn test_debug_default_arguments(outer: goosetest::Test&) {
    var argv: const u8[:][>..] = [];
    build::append_arguments(argv, "goose", "goosetest_root.goose", "./goosetest_generated/tests",
        arguments::Profile.Debug, false);
    assert(argv == ["goose", "build", "goosetest_root.goose", "-O0", "--debug", "-o",
        "./goosetest_generated/tests"]);
}

fn test_debug_offline_arguments(outer: goosetest::Test&) {
    var argv: const u8[:][>..] = [];
    build::append_arguments(argv, "compiler path/goose;$(literal)", "project path/entry.goose",
        "./generated output/tests;$(literal)", arguments::Profile.Debug, true);
    assert(argv == ["compiler path/goose;$(literal)", "build", "project path/entry.goose", "-O0", "--debug",
        "--offline", "-o", "./generated output/tests;$(literal)"]);
}

fn test_optimized_arguments(outer: goosetest::Test&) {
    var argv: const u8[:][>..] = [];
    build::append_arguments(argv, "/opt/goose/bin/goose", "target.goose", "./target/tests",
        arguments::Profile.Optimized, false);
    assert(argv == ["/opt/goose/bin/goose", "build", "target.goose", "-O2", "-o", "./target/tests"]);
    for value in argv {
        assert(value != "--debug");
        assert(value != "-O0");
    }
}

fn test_cache_partition_paths(outer: goosetest::Test&) {
    var legacy_debug: u8[>..] = [];
    assert(build::cache_home(legacy_debug, "", "default", arguments::Profile.Debug));
    assert(legacy_debug == "./goosetest_generated/cache/default/debug");
    var legacy_optimized: u8[>..] = [];
    assert(build::cache_home(legacy_optimized, "/tmp/compiler cache", "default", arguments::Profile.Optimized));
    assert(legacy_optimized == "/tmp/compiler cache/default/optimized");
    var configured: u8[>..] = [];
    assert(build::cache_home(configured, "relative cache", "core", arguments::Profile.Debug));
    assert(configured == "./relative cache/core/debug");
    var another_target: u8[>..] = [];
    assert(build::cache_home(another_target, "relative cache", "database", arguments::Profile.Debug));
    assert(another_target != configured);
    var long_root: u8[>..] = [];
    for index in 0..4090 {
        long_root.push('x');
    }
    var too_long: u8[>..] = [];
    assert(!build::cache_home(too_long, long_root, "default", arguments::Profile.Debug));
}
