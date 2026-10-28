// Format one bounded output record at a time; control bytes cannot create fake rows.
namespace cli_output;

import std;

import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.model;
import src.discovery.selection;
import src.execution.targets;

fn escaped(value: u8[:]) -> u8[>..] {
    var result: u8[>..] = [];
    let hex = "0123456789ABCDEF";
    for byte in value {
        if byte == '\\' {
            result.append("\\\\");
        } else if byte < 32 || byte == 127 {
            result.append("\\x");
            result.push(hex[(byte / 16)as i64]);
            result.push(hex[(byte % 16)as i64]);
        } else {
            result.push(byte);
        }
    }
    return result;
}

fn case_line(manifest: discovery::Manifest&, entry: discovery::Case) -> u8[>..] {
    let suite = manifest.suites[entry.suite_index];
    var kind: const u8[:] = "unit";
    if suite.kind == discovery::RootKind.Integration {
        kind = "integration";
    }
    return str(kind, "  ", discovery::manifest_text(manifest, entry.identity), "  (",
        discovery::manifest_text(manifest, suite.path), ":", entry.location.line, ":", entry.location.column, ")\n");
}

fn case_summary(manifest: discovery::Manifest&) -> u8[>..] {
    var disabled: i64 = 0;
    for entry in manifest.cases {
        if entry.disabled {
            disabled += 1;
        }
    }
    return str(manifest.cases.len, " discovered cases: ", manifest.cases.len - disabled,
        " executable, ", disabled, " disabled\n");
}

fn mirror_summary(audit: discovery::MirrorAudit&) -> u8[>..] {
    if audit.disabled {
        return str("Mirror enforcement is disabled for configured targets. Set mirror.policy to strict ",
            "with source/tests pairs.\n");
    }
    return str("Unit mirrors: ", audit.matched, " matched, ", audit.missing, " missing, ",
        audit.orphaned, " orphaned; ", audit.bad_names, " bad test filenames\n",
        "Integration suites: ", audit.integration_files, "\n");
}

fn selection_summary(manifest: discovery::Manifest&, options: selection::Options) -> u8[>..] {
    var count: i64 = 0;
    var disabled: i64 = 0;
    for entry in manifest.cases {
        if selection::matches(manifest, entry, options) {
            count += 1;
            if entry.disabled {
                disabled += 1;
            }
        }
    }
    return str(count, " selected cases: ", count - disabled, " executable, ", disabled,
        " disabled; ", manifest.cases.len - count, " excluded\n");
}

fn target_header(name: const u8[:], profile: const u8[:]) -> u8[>..] {
    return str("TARGET ", name, " PROFILE ", profile, ": starting\n");
}

fn target_summary(name: const u8[:], profile: const u8[:], result: targets::Result) -> u8[>..] {
    if result.state == targets::State.SelectionExcluded {
        return str("TARGET ", name, " PROFILE ", profile, ": selection excluded\n");
    }
    if result.state == targets::State.DisabledOnly {
        return str("TARGET ", name, " PROFILE ", profile, ": skipped (all cases disabled)\n");
    }
    if result.state == targets::State.Passed {
        return str("TARGET ", name, " PROFILE ", profile, ": passed (status 0)\n");
    }
    if result.state == targets::State.AssertionFailure {
        return str("TARGET ", name, " PROFILE ", profile, ": assertion failure (status 1)\n");
    }
    if result.state == targets::State.Incomplete {
        return str("TARGET ", name, " PROFILE ", profile, ": incomplete (status 2)\n");
    }
    if result.state == targets::State.Cancelled {
        return str("TARGET ", name, " PROFILE ", profile, ": cancelled (status ", result.status, ")\n");
    }
    return str("TARGET ", name, " PROFILE ", profile, ": NOT RUN\n");
}

fn aggregate_status(status: i32) -> u8[>..] {
    return str("Aggregate status: ", status, "\n");
}
