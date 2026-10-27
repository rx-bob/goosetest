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
    invalid(["test"]);
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
