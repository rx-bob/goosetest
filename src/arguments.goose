// Incremental CLI grammar; project bytes belong to the caller, never argv scratch.
namespace arguments;

enum Command {
    None,
    List,
    CheckMirror
}
struct Options {
    project: u8[>..]&,
    command: Command = Command.None,
    help: bool = false,
    project_seen: bool = false,
    needs_project: bool = false,
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
    if options.needs_project {
        options.needs_project = false;
        if value.len == 0 || (value.len >= 2 && value[..2] == "--") {
            options.error = "--project requires a nonempty path (use ./ for paths beginning with --)";
        } else if value.len > 4096 {
            options.error = "--project path exceeds 4096 bytes";
        } else {
            options.project.append(value);
        }
        return;
    }
    if value == "--project" {
        if options.project_seen {
            options.error = "--project may occur only once";
            return;
        }
        options.project_seen = true;
        options.needs_project = true;
    } else if value == "--help" {
        if options.help {
            options.error = "--help may occur only once";
            return;
        }
        options.help = true;
    } else if value == "list" || value == "check-mirror" {
        if options.command != Command.None {
            options.error = "choose exactly one command";
            return;
        }
        if value == "list" {
            options.command = Command.List;
        }
        else {
            options.command = Command.CheckMirror;
        }
    } else {
        options.error = "unknown argument; supported commands are list and check-mirror";
    }
}

fn finish(options: Options&) {
    if options.error.len > 0 {
        return;
    }
    if options.needs_project {
        options.error = "--project requires a path";
        return;
    }
    if options.command == Command.None && !options.help {
        options.error = "a command is required: list or check-mirror";
        return;
    }
    if !options.project_seen {
        options.project.append(".");
    }
}

fn help_text() -> const u8[:] {
    return """
Usage: goosetest <list|check-mirror> [--project PATH] [--help]
       goosetest --help

list          List all stable case IDs, source locations, kinds and disabled reasons.
check-mirror  Validate full layout and declarations; report file correspondence.
--project     Project directory; defaults to current directory. May precede command.
--help        Show help; other arguments must still be valid. No project is scanned.

Required src/ and test/: src/path/name.goose <-> test/path/name_test.goose.
Optional integration/: independent named *_test.goose suites. Every suite needs a test.
Put helpers in test_support/. Root entries/facades and generated output are not audited.
No exclusions, filters or execution options yet. These commands never compile or run tests.
Both commands validate the whole project; empty projects and incomplete discovery fail.
Only @DisplayName and @Disabled metadata are supported; disabled cases count as tests.

Default finite limits (bytes unless stated):
Filesystem: 65536 entries, depth 64, 4096 per path, 8388608 retained path bytes,
1048576 per file, 67108864 total source bytes. Symlinks under scanned roots are errors.
Syntax: 1048576 per file, 67108864 total, 262144 tokens/file, nesting 128,
4096 suites, 65536 cases, 8388608 retained metadata bytes.
Limits are fixed for this CLI release; no configuration file or override flags.
Exit: 0 valid list/audit/help; 2 usage, layout, discovery or resource error.
Exit 1 is reserved for executed assertion failures. Mirror counts are not code coverage.
""";
}
