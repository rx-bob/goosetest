// Argument grammar checks include ownership after temporary argv buffers disappear.
namespace arguments_test;

import std;

import goosetest.src.arguments;

fn test_valid() {
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

fn test_defaults() {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "check-mirror");
    arguments::finish(options);
    assert(options.error.len == 0 && project == ".");
    assert(options.command == arguments::Command.CheckMirror);
}

fn test_invalid() {
    invalid(["list", "--filter", "x"]);
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

fn test_help_and_limit() {
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

fn test_execution_options() {
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

fn test_execution_defaults() {
    var project: u8[>..] = [];
    var options = arguments::new_options(project);
    arguments::consume(options, "test");
    arguments::finish(options);
    assert(options.error.len == 0 && options.compiler == "goose");
    assert(options.compile_timeout_seconds == 120 && options.run_timeout_seconds == 120);
}

fn test_execution_invalid() {
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
