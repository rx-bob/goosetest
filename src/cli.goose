// All commands validate the complete project before listing or executing tests.
namespace cli;

import os;
import std;

import src.arguments;
import src.cli_output;
import src.config.load;
import src.config.model;
import src.discovery.errors;
import src.discovery.files;
import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.model;
import src.discovery.selection;
import src.execution.command;

fn run(options: arguments::Options&) -> i32 {
    if options.error.len > 0 {
        write_stderr(str("ERROR: ", options.error, "\n", arguments::help_text()));
        return 2;
    }
    if options.help {
        write_stdout(arguments::help_text());
        return 0;
    }
    var config_text: u8[>..] = [];
    var config_targets: config::Target[>..] = [];
    var config_roots: config::TestRoot[>..] = [];
    var config_exclusions: config::Exclusion[>..] = [];
    var config_pairs: config::MirrorPair[>..] = [];
    var configuration = config::new_configuration(
        config_text, config_targets, config_roots, config_exclusions, config_pairs
    );
    if config::load(configuration, options.project) != 0 {
        write_stderr(str("ERROR: ", configuration.field, ": ", configuration.error, "\n"));
        incomplete();
        return 2;
    }
    var files: discovery::SourceFile[>..] = [];
    var roots: discovery::RootRecord[>..] = [];
    var exclusions: discovery::ExclusionRule[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var error_path: u8[>..] = [];
    var buffers = discovery::InventoryBuffers {
        files: files,
        roots: roots,
        exclusions: exclusions,
        paths: paths,
        sources: sources,
        error_path: error_path,
    };
    var inventory = discovery::new_inventory(buffers);
    if configuration.configured {
        discovery::scan_configured(inventory, options.project, configuration);
    } else {
        discovery::scan(inventory, options.project);
    }
    if discovery::status(inventory) != 0 {
        write_stderr(str("ERROR: ", cli_output::escaped(discovery::error_text(inventory)), "\n"));
        incomplete();
        return 2;
    }
    return inspect(options, inventory);
}

fn inspect(options: arguments::Options&, inventory: discovery::Inventory&) -> i32 {
    var records: discovery::MirrorRecord[>..] = [];
    var audit = discovery::new_mirror_audit(records);
    var suites: discovery::Suite[>..] = [];
    var cases: discovery::Case[>..] = [];
    var text: u8[>..] = [];
    var error_path: u8[>..] = [];
    var manifest = discovery::new_manifest(suites, cases, text, error_path);
    discovery::inspect_project(audit, manifest, inventory);
    if audit.disabled && options.command == arguments::Command.CheckMirror {
        write_stderr(cli_output::mirror_summary(audit));
        incomplete();
        return 2;
    }
    if !audit.disabled && discovery::mirror_status(audit) != 0 {
        for record in audit.records {
            if record.kind != discovery::MirrorKind.Matched {
                write_stderr(str(discovery::mirror_record_text(inventory, record), "\n"));
            }
        }
        write_stderr(cli_output::mirror_summary(audit));
        if manifest.complete && discovery::manifest_status(manifest) != 0 {
            write_stderr(str("ERROR: ", discovery::manifest_error_text(manifest), "\n"));
        }
        incomplete();
        return 2;
    }
    if discovery::project_status(audit, manifest) != 0 {
        write_stderr(str("ERROR: ", discovery::manifest_error_text(manifest), "\n"));
        incomplete();
        return 2;
    }
    let selected = selection::Options {
        filter: options.filter,
        suite: options.suite
    };
    if options.command != arguments::Command.CheckMirror && selection::count(manifest, selected) == 0 {
        write_stderr("ERROR: selection matched zero cases; no tests executed.\n");
        return 2;
    }
    if options.command == arguments::Command.Test {
        return command::run(options, manifest, audit);
    }
    if options.command == arguments::Command.List {
        list_cases(manifest, selected, options.filter_seen || options.suite_seen);
    } else {
        for record in audit.records {
            write_stdout(str(discovery::mirror_record_text(inventory, record), "\n"));
        }
        write_stdout(cli_output::mirror_summary(audit));
    }
    return 0;
}

fn list_cases(manifest: discovery::Manifest&, selected: selection::Options, explicit: bool) {
    for entry in manifest.cases {
        if !selection::matches(manifest, entry, selected) {
            continue;
        }
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
    if explicit {
        write_stdout(cli_output::selection_summary(manifest, selected));
    } else {
        write_stdout(cli_output::case_summary(manifest));
    }
}

fn incomplete() {
    write_stderr("Discovery incomplete; no tests executed.\n");
}
