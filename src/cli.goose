// Read-only command dispatch shares complete project validation with future execution.
namespace cli;

import os;
import std;

import src.arguments;
import src.cli_output;
import src.discovery.errors;
import src.discovery.files;
import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.model;

fn run(options: arguments::Options&) -> i32 {
    if options.error.len > 0 {
        write_stderr(str("ERROR: ", options.error, "\n", arguments::help_text()));
        return 2;
    }
    if options.help {
        write_stdout(arguments::help_text());
        return 0;
    }
    var files: discovery::SourceFile[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var error_path: u8[>..] = [];
    var inventory = discovery::new_inventory(files, paths, sources, error_path);
    discovery::scan(inventory, options.project);
    if discovery::status(inventory) != 0 {
        write_stderr(str("ERROR: ", cli_output::escaped(discovery::error_text(inventory)), "\n"));
        incomplete();
        return 2;
    }
    return inspect(options.command, inventory);
}

fn inspect(command: arguments::Command, inventory: discovery::Inventory&) -> i32 {
    var records: discovery::MirrorRecord[>..] = [];
    var audit = discovery::new_mirror_audit(records);
    var suites: discovery::Suite[>..] = [];
    var cases: discovery::Case[>..] = [];
    var text: u8[>..] = [];
    var error_path: u8[>..] = [];
    var manifest = discovery::new_manifest(suites, cases, text, error_path);
    discovery::inspect_project(audit, manifest, inventory);
    if discovery::mirror_status(audit) != 0 {
        for record in audit.records {
            if record.kind != discovery::MirrorKind.Matched {
                write_stderr(str(discovery::mirror_record_text(inventory, record), "\n"));
            }
        }
        write_stderr(cli_output::mirror_summary(audit));
        incomplete();
        return 2;
    }
    if discovery::project_status(audit, manifest) != 0 {
        write_stderr(str("ERROR: ", discovery::manifest_error_text(manifest), "\n"));
        incomplete();
        return 2;
    }
    if command == arguments::Command.List {
        list_cases(manifest);
    }
    else {
        for record in audit.records {
            write_stdout(str(discovery::mirror_record_text(inventory, record), "\n"));
        }
        write_stdout(cli_output::mirror_summary(audit));
    }
    return 0;
}

fn list_cases(manifest: discovery::Manifest&) {
    for entry in manifest.cases {
        write_stdout(cli_output::case_line(manifest, entry));
        if entry.has_display {
            write_stdout(str("      display: ", cli_output::escaped(discovery::manifest_text(manifest,
                entry.display_name)), "\n"));
        }
        if entry.disabled {
            write_stdout(str("      disabled: ", cli_output::escaped(discovery::manifest_text(manifest,
                entry.disabled_reason)), "\n"));
        }
    }
    write_stdout(cli_output::case_summary(manifest));
}

fn incomplete() {
    write_stderr("Discovery incomplete; no tests executed.\n");
}
