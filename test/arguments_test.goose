// Argument grammar checks include ownership after temporary argv buffers disappear.
namespace arguments_test;

import std;

import goosetest;
import src.arguments;
import src.discovery.selection;

fn test_valid(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "--project");
    temporary_path(options);
    arguments::consume(options, "list");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.command == arguments::Command.List);
    assert(project == "path with spaces");
}

fn temporary_path(options: arguments::Options&) {
    let path = str("path with", " spaces");
    arguments::consume(options, path);
}

fn test_defaults(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "check-mirror");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(project == ".");
    assert(options.command == arguments::Command.CheckMirror);
}

fn test_invalid(outer: goosetest::Test&) {
    invalid(["check-mirror", "--filter", "x"]);
    invalid(["test", "list"]);
    invalid(["list", "check-mirror"]);
    invalid(["list", "--project"]);
    invalid(["list", "--project", ""]);
    invalid(["list", "--project", "--help"]);
    invalid(["list", "--project", ".", "--project", "."]);
    invalid(["--project", "."]);
    invalid(["--help", "--bogus"]);
    invalid(["--help", "--help"]);
    invalid(["list", "extra"]);
    invalid([]);
}

fn invalid(values: const u8[:][:]) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    for value in values {
        arguments::consume(options, value);
    }
    arguments::finish(options);
    assert(options.error.len > 0);
}

fn test_help_and_limit(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "list");
    arguments::consume(options, "--help");
    arguments::finish(options);
    assert(options.help);
    assert(options.error.len == 0);
    var long_path: u8[>..] = [];
    for index in 0..4097 {
        long_path.push('a');
    }
    invalid(["list", "--project", long_path]);
}

fn test_execution_options(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "--compiler");
    temporary_compiler(options);
    arguments::consume(options, "test");
    arguments::consume(options, "--compile-timeout-seconds");
    arguments::consume(options, "1");
    arguments::consume(options, "--run-timeout-seconds");
    arguments::consume(options, "86400");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.command == arguments::Command.Test);
    assert(options.compiler == "compiler path/goose");
    assert(options.compile_timeout_seconds == 1);
    assert(options.run_timeout_seconds == 86400);
}

fn temporary_compiler(options: arguments::Options&) {
    let path = str("compiler path/", "goose");
    arguments::consume(options, path);
}

fn test_execution_defaults(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "test");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.compiler == "goose");
    assert(options.compile_timeout_seconds == 120);
    assert(options.run_timeout_seconds == 120);
}

fn test_profile_options(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "test");
    arguments::consume(options, "--profile");
    arguments::consume(options, "optimized");
    arguments::consume(options, "--offline");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.profile == arguments::Profile.Optimized);
    assert(options.offline);
    var default_project: u8[>..] = [];
    var defaults = arguments::new_options(default_project);
    arguments::consume(defaults, "test");
    arguments::finish(defaults);
    assert(defaults.error.len == 0);
    assert(defaults.profile == arguments::Profile.Debug);
    assert(!defaults.offline);
}

fn test_cache_root_option(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "--cache-root");
    arguments::consume(options, "relative cache/root");
    arguments::consume(options, "test");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.cache_root == "relative cache/root");
    invalid(["test", "--cache-root"]);
    invalid(["test", "--cache-root", ""]);
    invalid(["test", "--cache-root", "--other"]);
    invalid(["test", "--cache-root", "bad\0path"]);
    invalid(["test", "--cache-root", "one", "--cache-root", "two"]);
    invalid(["list", "--cache-root", "cache"]);
    invalid(["check-mirror", "--cache-root", "cache"]);
    invalid(["--help", "--cache-root", "cache"]);
    var long_path: u8[>..] = [];
    for index in 0..4097 {
        long_path.push('a');
    }
    invalid(["test", "--cache-root", long_path]);
}

fn test_execution_invalid(outer: goosetest::Test&) {
    invalid(["list", "--compiler", "goose"]);
    invalid(["check-mirror", "--run-timeout-seconds", "1"]);
    invalid(["--help", "--compile-timeout-seconds", "1"]);
    invalid(["test", "--compiler"]);
    invalid(["test", "--compiler", ""]);
    invalid(["test", "--compiler", "--help"]);
    invalid(["test", "--compiler", "bad\0path"]);
    invalid(["test", "--compiler", "goose", "--compiler", "goose"]);
    invalid(["test", "--profile"]);
    invalid(["test", "--profile", ""]);
    invalid(["test", "--profile", "both"]);
    invalid(["test", "--profile", "release"]);
    invalid(["test", "--profile", "debug", "--profile", "optimized"]);
    invalid(["test", "--offline", "--offline"]);
    invalid(["list", "--profile", "debug"]);
    invalid(["check-mirror", "--offline"]);
    invalid(["--help", "--profile", "optimized"]);
    invalid(["test", "--compile-timeout-seconds"]);
    invalid(["test", "--run-timeout-seconds", ""]);
    invalid(["test", "--run-timeout-seconds", "0"]);
    invalid(["test", "--run-timeout-seconds", "-1"]);
    invalid(["test", "--run-timeout-seconds", "1.5"]);
    invalid(["test", "--run-timeout-seconds", "86401"]);
    invalid(["test", "--run-timeout-seconds", "99999999999999999999999999"]);
    invalid(["test", "--run-timeout-seconds", "1", "--run-timeout-seconds", "2"]);
    invalid(["test", "--compile-timeout-seconds", "1", "--compile-timeout-seconds", "2"]);
    var long_path: u8[>..] = [];
    for index in 0..4097 {
        long_path.push('a');
    }
    invalid(["test", "--compiler", long_path]);
}

fn test_selection_options(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "--filter");
    temporary_filter(options);
    arguments::consume(options, "--suite");
    arguments::consume(options, "integration");
    arguments::consume(options, "test");
    arguments::consume(options, "--fail-fast");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.filter == "test_[a]+.*");
    assert(options.suite == selection::Suite.Integration);
    assert(options.fail_fast);
}

fn temporary_filter(options: arguments::Options&) {
    let value = str("test_", "[a]+.*");
    arguments::consume(options, value);
}

fn test_selection_empty_and_defaults(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "list");
    arguments::consume(options, "--filter");
    arguments::consume(options, "");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.filter.len == 0);
    assert(options.filter_seen);
    assert(options.suite == selection::Suite.All);
    assert(!options.fail_fast);
    var other_project: u8[>..] = [];
    var other = arguments::new_options(other_project);
    arguments::consume(other, "list");
    arguments::consume(other, "--filter");
    arguments::consume(other, "--literal");
    arguments::consume(other, "--suite");
    arguments::consume(other, "unit");
    arguments::finish(other);
    assert(other.error.len == 0);
    assert(other.filter == "--literal");
    assert(other.suite == selection::Suite.Unit);
}

fn test_selection_invalid(outer: goosetest::Test&) {
    invalid(["list", "--filter"]);
    invalid(["test", "--suite"]);
    invalid(["test", "--suite", ""]);
    invalid(["test", "--suite", "wrong"]);
    invalid(["test", "--suite", "unit", "--suite", "all"]);
    invalid(["list", "--filter", "x", "--filter", "y"]);
    invalid(["list", "--fail-fast"]);
    invalid(["test", "--fail-fast", "--fail-fast"]);
    invalid(["check-mirror", "--suite", "all"]);
    invalid(["--help", "--filter", "x"]);
    invalid(["list", "--filter", "bad\0value"]);
    var value: u8[>..] = [];
    for index in 0..4096 {
        value.push('x');
    }
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "list");
    arguments::consume(options, "--filter");
    arguments::consume(options, value);
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.filter.len == 4096);
    value.push('x');
    invalid(["list", "--filter", value]);
}

fn test_target_selection_options(outer: goosetest::Test&) {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "--target");
    arguments::consume(options, "http_2");
    arguments::consume(options, "list");
    arguments::consume(options, "--target");
    arguments::consume(options, "core");
    arguments::finish(options);
    assert(options.error.len == 0);
    assert(options.target_count == 2);
    assert(options.targets == "http_2\0core\0");

    var all_project: u8[>..] = [];
    var all = arguments::new_options(all_project);
    arguments::consume(all, "--target");
    arguments::consume(all, "all");
    arguments::consume(all, "check-mirror");
    arguments::finish(all);
    assert(all.error.len == 0);
    assert(all.target_all);
    assert(all.target_count == 0);
}

fn test_target_selection_invalid(outer: goosetest::Test&) {
    invalid(["list", "--target"]);
    invalid(["list", "--target", ""]);
    invalid(["list", "--target", "Core"]);
    invalid(["list", "--target", "core-name"]);
    invalid(["list", "--target", "all", "--target", "core"]);
    invalid(["list", "--target", "core", "--target", "all"]);
    invalid(["list", "--target", "all", "--target", "all"]);
    invalid(["test", "--target", "core", "--target", "core"]);
    invalid(["check-mirror", "--target", "bad\0name"]);
    invalid(["--help", "--target", "core"]);
}
