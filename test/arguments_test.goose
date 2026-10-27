// Argument grammar checks include ownership after temporary argv buffers disappear.
namespace arguments_test;

import goosetest;

import std;

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
    assert(options.error.len == 0 && project == ".");
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
    assert(options.help && options.error.len == 0);
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
    assert(options.error.len == 0 && options.compiler == "goose");
    assert(options.compile_timeout_seconds == 120 && options.run_timeout_seconds == 120);
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
    assert(options.error.len == 0 && options.filter.len == 0 && options.filter_seen);
    assert(options.suite == selection::Suite.All && !options.fail_fast);
    var other_project: u8[>..] = [];
    var other = arguments::new_options(other_project);
    arguments::consume(other, "list");
    arguments::consume(other, "--filter");
    arguments::consume(other, "--literal");
    arguments::consume(other, "--suite");
    arguments::consume(other, "unit");
    arguments::finish(other);
    assert(other.error.len == 0 && other.filter == "--literal");
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
    assert(options.error.len == 0 && options.filter.len == 4096);
    value.push('x');
    invalid(["list", "--filter", value]);
}
