// Format one bounded output record at a time; control bytes cannot create fake rows.
namespace cli_output;

import std;

import src.discovery.manifest;
import src.discovery.mirror;
import src.discovery.model;
import src.discovery.selection;

fn escaped(value: u8[:]) -> u8[>..] {
    var result: u8[>..] = [];
    let hex = "0123456789ABCDEF";
    for byte in value {
        if byte == '\\' {
            result.append("\\\\");
        }
        else if byte < 32 || byte == 127 {
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
