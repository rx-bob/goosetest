// Incremental CLI grammar owns every value beyond temporary argv storage.
namespace arguments;

import src.discovery.selection;

enum Command {
    None,
    List,
    CheckMirror,
    Test
}
enum Pending {
    None,
    Project,
    Compiler,
    Profile,
    CompileTimeout,
    RunTimeout,
    Filter,
    Suite
}
enum Profile {
    Debug,
    Optimized
}
struct Options {
    project: u8[>..]&,
    compiler: u8[..4096] = [],
    profile: Profile = Profile.Debug,
    filter: u8[..4096] = [],
    suite: selection::Suite = selection::Suite.All,
    filter_seen: bool = false,
    suite_seen: bool = false,
    fail_fast: bool = false,
    command: Command = Command.None,
    pending: Pending = Pending.None,
    help: bool = false,
    project_seen: bool = false,
    compiler_seen: bool = false,
    profile_seen: bool = false,
    offline: bool = false,
    compile_timeout_seen: bool = false,
    run_timeout_seen: bool = false,
    compile_timeout_seconds: i64 = 120,
    run_timeout_seconds: i64 = 120,
    error: const u8[:] = "",
}

fn new_options(project: u8[>..]&) -> Options {
    assert(project.len == 0);
    return Options {
        project: project,
        ..
    };
}

fn consume(options: Options&, value: u8[:]) {
    if options.error.len > 0 {
        return;
    }
    if options.pending != Pending.None {
        consume_value(options, value);
        return;
    }
    if value == "--project" {
        expect_value(options, Pending.Project, options.project_seen);
        options.project_seen = true;
    } else if value == "--compiler" {
        expect_value(options, Pending.Compiler, options.compiler_seen);
        options.compiler_seen = true;
    } else if value == "--profile" {
        expect_value(options, Pending.Profile, options.profile_seen);
        options.profile_seen = true;
    } else if value == "--compile-timeout-seconds" {
        expect_value(options, Pending.CompileTimeout, options.compile_timeout_seen);
        options.compile_timeout_seen = true;
    } else if value == "--run-timeout-seconds" {
        expect_value(options, Pending.RunTimeout, options.run_timeout_seen);
        options.run_timeout_seen = true;
    } else if value == "--filter" {
        expect_value(options, Pending.Filter, options.filter_seen);
        options.filter_seen = true;
    } else if value == "--suite" {
        expect_value(options, Pending.Suite, options.suite_seen);
        options.suite_seen = true;
    } else if value == "--fail-fast" {
        if options.fail_fast {
            options.error = "--fail-fast may occur only once";
        }
        options.fail_fast = true;
    } else if value == "--offline" {
        if options.offline {
            options.error = "--offline may occur only once";
        }
        options.offline = true;
    } else if value == "--help" {
        if options.help {
            options.error = "--help may occur only once";
        }
        options.help = true;
    } else if value == "list" || value == "check-mirror" || value == "test" {
        consume_command(options, value);
    } else {
        options.error = "unknown argument; supported commands are list, check-mirror and test";
    }
}

fn expect_value(options: Options&, pending: Pending, seen: bool) {
    if seen {
        options.error = "each option may occur only once";
    } else {
        options.pending = pending;
    }
}

fn consume_command(options: Options&, value: u8[:]) {
    if options.command != Command.None {
        options.error = "choose exactly one command";
    } else if value == "list" {
        options.command = Command.List;
    } else if value == "check-mirror" {
        options.command = Command.CheckMirror;
    } else {
        options.command = Command.Test;
    }
}

fn consume_value(options: Options&, value: u8[:]) {
    let pending = options.pending;
    options.pending = Pending.None;
    if pending == Pending.Filter {
        consume_filter(options, value);
        return;
    }
    if pending == Pending.Suite {
        consume_suite(options, value);
        return;
    }
    if pending == Pending.Profile {
        if value == "debug" {
            options.profile = Profile.Debug;
        } else if value == "optimized" {
            options.profile = Profile.Optimized;
        } else {
            options.error = "--profile must be debug or optimized";
        }
        return;
    }
    if value.len == 0 || (value.len >= 2 && value[..2] == "--") {
        options.error = "option requires a nonempty value (use ./ for paths beginning with --)";
        return;
    }
    if pending == Pending.CompileTimeout || pending == Pending.RunTimeout {
        let seconds = timeout_seconds(value);
        if seconds == 0 {
            options.error = "timeout must be an integer from 1 through 86400 seconds";
        } else if pending == Pending.CompileTimeout {
            options.compile_timeout_seconds = seconds;
        } else {
            options.run_timeout_seconds = seconds;
        }
        return;
    }
    if value.len > 4096 {
        options.error = "path exceeds 4096 bytes";
        return;
    }
    for byte in value {
        if byte == 0 {
            options.error = "paths must not contain NUL bytes";
            return;
        }
    }
    if pending == Pending.Project {
        options.project.append(value);
    } else {
        options.compiler.append(value);
    }
}

fn consume_filter(options: Options&, value: u8[:]) {
    if value.len > 4096 {
        options.error = "--filter exceeds 4096 bytes";
        return;
    }
    for byte in value {
        if byte == 0 {
            options.error = "--filter must not contain NUL bytes";
            return;
        }
    }
    options.filter.append(value);
}

fn consume_suite(options: Options&, value: u8[:]) {
    if value == "unit" {
        options.suite = selection::Suite.Unit;
    } else if value == "integration" {
        options.suite = selection::Suite.Integration;
    } else if value == "all" {
        options.suite = selection::Suite.All;
    } else {
        options.error = "--suite must be unit, integration or all";
    }
}

fn timeout_seconds(value: u8[:]) -> i64 {
    var result: i64 = 0;
    for byte in value {
        if byte < '0' || byte > '9' || result > 8640 {
            return 0;
        }
        result = result * 10 + (byte - '0');
        if result > 86400 {
            return 0;
        }
    }
    return result;
}

fn finish(options: Options&) {
    if options.error.len > 0 {
        return;
    }
    if options.pending != Pending.None {
        options.error = "option requires a value";
        return;
    }
    if options.command == Command.None && !options.help {
        options.error = "a command is required: list, check-mirror or test";
        return;
    }
    if options.command != Command.Test
        && (options.compiler_seen || options.profile_seen || options.offline || options.compile_timeout_seen
        || options.run_timeout_seen || options.fail_fast) {
        options.error = "compiler, profile, offline, timeout and fail-fast options require the test command";
        return;
    }
    if options.command != Command.List && options.command != Command.Test
        && (options.filter_seen || options.suite_seen) {
        options.error = "filter and suite options require list or test";
        return;
    }
    if !options.project_seen {
        options.project.append(".");
    }
    if !options.compiler_seen {
        options.compiler.append("goose");
    }
}

fn help_text() -> const u8[:] {
    return """
Usage: goosetest <list|check-mirror|test> [--project PATH] [--help]
       goosetest --help

list          List selected stable IDs, source locations, kinds and disabled reasons.
test          Discover, generate, compile and execute.
check-mirror  Validate full layout and declarations; report file correspondence.
--project     Project directory; defaults to current directory. May precede command.
--compiler PATH                Test compiler executable; default goose, resolved through PATH.
--profile debug|optimized      Compiler profile for test; default debug.
--offline                      Test only: do not fetch missing compiler dependencies.
--compile-timeout-seconds N     Compilation deadline; default 120 seconds.
--run-timeout-seconds N         Execution deadline; default 120 seconds.
Timeouts accept integers 1 through 86400; termination grace is 1 second.
--filter TEXT                  Literal stable-ID substring for list/test; default empty (all).
--suite unit|integration|all    Case kind for list/test; default all.
--fail-fast                    Test only: finish case/suite cleanup, then stop further bodies.
Filter text is at most 4096 bytes; an explicit empty filter matches all IDs.
--help        Show help; other arguments must still be valid. No project is scanned.

Required src/ and test/: src/path/name.goose <-> test/path/name_test.goose.
Optional integration/: independent named *_test.goose suites. Every suite needs a test.
Put helpers in test_support/. Root entries/facades and generated output are not audited.
Selection never weakens the full audit or typechecking. list and check-mirror never compile or run tests.
Configured projects currently support one target end to end; multi-target execution arrives in a later release.
Only @DisplayName and @Disabled metadata are supported; disabled cases compile but never execute.

Default finite limits (bytes unless stated):
Filesystem: 65536 entries, depth 64, 4096 per path, 8388608 retained path bytes,
1048576 per file, 67108864 total source bytes. Symlinks under scanned roots are errors.
Syntax: 1048576 per file, 67108864 total, 262144 tokens/file, nesting 128,
4096 suites, 65536 cases, 8388608 retained metadata bytes.
Discovery limits are fixed. goosetest.json is bounded and validated; one configured target is supported.
Exit: 0 valid list/audit/help or completed passing tests; 1 executed assertion failures;
2 usage, discovery, generation, compilation, process, deadline or incomplete-run error.
Cancellation preserves conventional interruption status. Mirror counts are not code coverage.
""";
}
