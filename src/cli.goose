// All selected targets pass discovery and syntax preflight before output or execution starts.
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
import src.discovery.paths;
import src.discovery.selection;
import src.execution.command;
import src.execution.targets;
import src.generation.model;
import src.generation.runner;
import src.platform.filesystem;
import src.platform.staging;

struct TargetExecution {
    selected: i64[:],
    match_counts: i64[:],
    executable_counts: i64[:],
    fd: i32,
}

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
    return run_project(options, configuration);
}

fn run_project(options: arguments::Options&, configuration: config::Configuration&) -> i32 {
    var selected: i64[>..] = [];
    if !resolve_targets(options, configuration, selected) {
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
        discovery::scan_configured(inventory, options.project, configuration, selected);
    } else {
        discovery::scan(inventory, options.project);
    }
    if discovery::status(inventory) != 0 {
        write_stderr(str("ERROR: ", cli_output::escaped(discovery::error_text(inventory)), "\n"));
        incomplete();
        return 2;
    }
    return run_selected(options, configuration, selected, inventory);
}

fn run_selected(
    options: arguments::Options&, configuration: config::Configuration&, selected: i64[:],
    inventory: discovery::Inventory&
) -> i32 {
    var total_matches: i64 = 0;
    var match_counts: i64[>..] = [];
    var executable_counts: i64[>..] = [];
    for target_index in selected {
        let target = selected_target(configuration, target_index);
        var executable: i64 = 0;
        let count = preflight_target(options, inventory, configuration, target_index, target, executable);
        if count < 0 {
            return 2;
        }
        match_counts.push(count);
        executable_counts.push(executable);
        total_matches += count;
    }
    if options.command != arguments::Command.CheckMirror && total_matches == 0 {
        write_stderr("ERROR: selection matched zero cases; no tests executed.\n");
        incomplete();
        return 2;
    }
    if options.command == arguments::Command.Test {
        return execute_targets(options, configuration, inventory, selected, match_counts, executable_counts);
    }
    var status: i32 = 0;
    for target_index, offset in selected {
        if options.command == arguments::Command.Test && match_counts[offset] == 0 {
            continue;
        }
        let target = selected_target(configuration, target_index);
        let result = render_target(options, inventory, configuration, target_index, target, -1);
        if result.status == 2 {
            return 2;
        }
        if result.status == 1 {
            status = 1;
        }
    }
    return status;
}

fn execute_targets(
    options: arguments::Options&, configuration: config::Configuration&, inventory: discovery::Inventory&,
    selected: i64[:], match_counts: i64[:], executable_counts: i64[:]
) -> i32 {
    let fd = create_execution_lock(options, configuration, selected, match_counts);
    if fd < 0 {
        return 2;
    }
    if !validate_selected_entries(configuration, selected, match_counts, fd) {
        filesystem::close_project(fd);
        incomplete();
        return 2;
    }
    var results: targets::Result[>..] = [];
    initialize_results(results, match_counts);
    let execution = TargetExecution {
        selected: selected,
        match_counts: match_counts,
        executable_counts: executable_counts,
        fd: fd,
    };
    run_selected_targets(options, configuration, inventory, execution, results);
    var status = targets::aggregate(results);
    let closed = filesystem::close_project(fd);
    if closed != 0 {
        write_stderr(str("ERROR: execution lock release: ", closed, "\n"));
        status = 2;
    }
    print_target_summary(options, configuration, selected, results, status);
    return status;
}

fn create_execution_lock(options: arguments::Options&, configuration: config::Configuration&,
    selected: i64[:], match_counts: i64[:]) -> i32 {
    var first_target_index: i64 = -2;
    for target_index, offset in selected {
        if match_counts[offset] > 0 {
            first_target_index = target_index;
            break;
        }
    }
    assert(first_target_index != -2);
    let first_target = selected_target(configuration, first_target_index);
    let fd = staging::create(options.project, first_target.entry);
    if fd < 0 {
        write_stderr(str("ERROR: execution lock, entry validation, or generated artifacts for target ",
            target_label(first_target),
            ": native error ", -fd, "; run incomplete.\n"));
        return fd;
    }
    return fd;
}

fn validate_selected_entries(configuration: config::Configuration&, selected: i64[:], match_counts: i64[:],
    fd: i32) -> bool {
    var first_target_index: i64 = -2;
    for target_index, offset in selected {
        if match_counts[offset] > 0 {
            first_target_index = target_index;
            break;
        }
    }
    assert(first_target_index != -2);
    for target_index in selected {
        let target = selected_target(configuration, target_index);
        let valid = if target_index == first_target_index {
            0
        } else {
            staging::verify_entry(fd, target.entry)
        };
        if valid != 0 {
            write_stderr(str("ERROR: entry validation for target ", target_label(target),
                ": native error ", -valid, "; no target was built.\n"));
            return false;
        }
    }
    return true;
}

fn initialize_results(results: targets::Result[>..]&, match_counts: i64[:]) {
    for count in match_counts {
        if count == 0 {
            results.push(targets::selection_excluded());
        } else {
            results.push(targets::not_run());
        }
    }
}

fn run_selected_targets(options: arguments::Options&, configuration: config::Configuration&,
    inventory: discovery::Inventory&, execution: TargetExecution, results: targets::Result[:]) {
    for target_index, offset in execution.selected {
        if execution.match_counts[offset] == 0 {
            let target = selected_target(configuration, target_index);
            write_stdout(str("TARGET ", target_label(target), ": selection excluded; no compiler call\n"));
            continue;
        }
        let target = selected_target(configuration, target_index);
        write_stdout(cli_output::target_header(target_label(target), profile_name(options.profile)));
        let result = render_target(options, inventory, configuration, target_index, target, execution.fd);
        let outcome = targets::from_execution(result.status, execution.executable_counts[offset],
            result.continue_allowed);
        results[offset] = outcome;
        if !targets::should_continue(outcome, options.fail_fast) {
            break;
        }
    }
}

fn print_target_summary(options: arguments::Options&, configuration: config::Configuration&,
    selected: i64[:], results: targets::Result[:], status: i32) {
    write_stdout(str("Target summary (profile ", profile_name(options.profile), "):\n"));
    for target_index, offset in selected {
        let target = selected_target(configuration, target_index);
        write_stdout(cli_output::target_summary(target_label(target), profile_name(options.profile),
            results[offset]));
    }
    write_stdout(cli_output::aggregate_status(status));
}

fn resolve_targets(options: arguments::Options&, configuration: config::Configuration&, selected: i64[>..]&) -> bool {
    if !configuration.configured {
        if options.target_count > 0 {
            if options.targets != "default\0" {
                write_stderr("ERROR: target is not configured: default\n");
                return false;
            }
        }
        selected.push(-1);
        return true;
    }
    if options.target_count == 0 && !options.target_all {
        for index in 0..configuration.targets.len {
            selected.push(index);
        }
    } else if options.target_all {
        for index in 0..configuration.targets.len {
            selected.push(index);
        }
    } else {
        var start: i64 = 0;
        while start < options.targets.len {
            var end = start;
            while end < options.targets.len && options.targets[end] != 0 {
                end += 1;
            }
            let name = options.targets[start..end];
            var found: i64 = -1;
            for index in 0..configuration.targets.len {
                let target = configuration.targets[index];
                if config::text_value(configuration, target.name) == name {
                    found = index;
                    break;
                }
            }
            if found < 0 {
                write_stderr(str("ERROR: unknown target: ", name, "\n"));
                return false;
            }
            selected.push(found);
            start = end + 1;
        }
    }
    sort(selected) {
        a,
        b => discovery::bytewise_less(
            config::text_value(configuration, configuration.targets[a].name),
            config::text_value(configuration, configuration.targets[b].name)
        )
    };
    return true;
}

fn selected_target(configuration: config::Configuration&, target_index: i64) -> command::Target {
    if target_index < 0 {
        return command::Target {
            name: "",
            entry: "goosetest_root.goose",
        };
    }
    let target = configuration.targets[target_index];
    return command::Target {
        name: config::text_value(configuration, target.name),
        entry: config::text_value(configuration, target.entry),
    };
}

fn preflight_target(
    options: arguments::Options&, inventory: discovery::Inventory&, configuration: config::Configuration&,
    target_index: i64, target: command::Target, executable: i64&
) -> i64 {
    var records: discovery::MirrorRecord[>..] = [];
    var audit = discovery::new_mirror_audit(records);
    var suites: discovery::Suite[>..] = [];
    var cases: discovery::Case[>..] = [];
    var text: u8[>..] = [];
    var error_path: u8[>..] = [];
    var manifest = discovery::new_manifest(suites, cases, text, error_path);
    discovery::set_target_name(manifest, target.name);
    discovery::inspect_project(audit, manifest, inventory, target_index);
    if audit.disabled && options.command == arguments::Command.CheckMirror {
        write_stderr(cli_output::mirror_summary(audit));
        incomplete();
        return -1;
    }
    if !audit.disabled && discovery::mirror_status(audit) != 0 {
        report_mirror_errors(inventory, audit);
        incomplete();
        return -1;
    }
    if discovery::project_status(audit, manifest) != 0 {
        write_stderr(str("ERROR: ", discovery::manifest_error_text(manifest), "\n"));
        incomplete();
        return -1;
    }
    if options.command == arguments::Command.CheckMirror {
        return 0;
    }
    let count = selection::count(manifest, selection_options(options));
    executable = executable_count(manifest, selection_options(options));
    if options.command == arguments::Command.Test && count > 0 &&
    !generation_preflight(manifest, audit, options) {
        return -1;
    }
    return count;
}

fn executable_count(manifest: discovery::Manifest&, selected: selection::Options) -> i64 {
    var count: i64 = 0;
    for entry in manifest.cases {
        if !entry.disabled && selection::matches(manifest, entry, selected) {
            count += 1;
        }
    }
    return count;
}

fn generation_preflight(manifest: discovery::Manifest&, audit: discovery::MirrorAudit&,
    options: arguments::Options&) -> bool {
    var modules: generation::Module[>..] = [];
    var paths: u8[>..] = [];
    var sources: u8[>..] = [];
    var errors: u8[>..] = [];
    var output = generation::new_output(modules, paths, sources, errors);
    generation::generate(output, manifest, audit, selection_options(options), options.fail_fast);
    if generation::status(output) != 0 {
        write_stderr(str("ERROR: generation: ", output.error,
            "\nRun incomplete; no tests executed.\n"));
        return false;
    }
    return true;
}

fn render_target(
    options: arguments::Options&, inventory: discovery::Inventory&, configuration: config::Configuration&,
    target_index: i64, target: command::Target, fd: i32
) -> command::Result {
    var records: discovery::MirrorRecord[>..] = [];
    var audit = discovery::new_mirror_audit(records);
    var suites: discovery::Suite[>..] = [];
    var cases: discovery::Case[>..] = [];
    var text: u8[>..] = [];
    var error_path: u8[>..] = [];
    var manifest = discovery::new_manifest(suites, cases, text, error_path);
    discovery::set_target_name(manifest, target.name);
    discovery::inspect_project(audit, manifest, inventory, target_index);
    if options.command == arguments::Command.Test {
        return command::run_locked(options, manifest, audit, target, fd);
    }
    if options.command == arguments::Command.List {
        list_cases(manifest, selection_options(options), options.filter_seen || options.suite_seen);
    } else {
        for record in audit.records {
            write_stdout(str(discovery::mirror_record_text(inventory, record), "\n"));
        }
        write_stdout(cli_output::mirror_summary(audit));
    }
    return command::Result {
        status: 0,
        continue_allowed: true,
    };
}

fn target_label(target: command::Target) -> const u8[:] {
    if target.name.len == 0 {
        return "default";
    }
    return target.name;
}

fn profile_name(profile: arguments::Profile) -> const u8[:] {
    if profile == arguments::Profile.Optimized {
        return "optimized";
    }
    return "debug";
}

fn selection_options(options: arguments::Options&) -> selection::Options {
    return selection::Options {
        filter: options.filter,
        suite: options.suite
    };
}

fn report_mirror_errors(inventory: discovery::Inventory&, audit: discovery::MirrorAudit&) {
    for record in audit.records {
        if record.kind != discovery::MirrorKind.Matched {
            write_stderr(str(discovery::mirror_record_text(inventory, record), "\n"));
        }
    }
    write_stderr(cli_output::mirror_summary(audit));
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
