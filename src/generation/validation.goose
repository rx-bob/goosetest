// Validate identifier channels separately from data; unsupported semantics never disappear.
namespace generation;

import std;

import src.discovery.manifest;
import src.discovery.model;
import src.discovery.paths;
import src.generation.model;

fn validate(output: Output&, manifest: discovery::Manifest&) {
    for suite in manifest.suites {
        let path = discovery::manifest_text(manifest, suite.path);
        let name = discovery::manifest_text(manifest, suite.namespace_name);
        if !identifier(name) || (name.len >= 19 && name[..19] == "goosetest_generated") {
            fail(output, path, "invalid namespace: maximum 48 bytes; goosetest_generated* is reserved");
        }
        if !valid_path(path, suite.kind) {
            fail(output, path, "invalid or overlong test module path (maximum 100 bytes)");
        }
    }
    for entry in manifest.cases {
        let suite = manifest.suites[entry.suite_index];
        let path = discovery::manifest_text(manifest, suite.path);
        let name = discovery::manifest_text(manifest, entry.name);
        if !identifier(name) {
            fail(output, path, "test identifier exceeds 48 bytes or is invalid");
        }
        if entry.disabled && entry.disabled_reason.length > 1024 {
            fail(output, path, "disabled reason exceeds generation limit of 1024 bytes");
        }
        if discovery::manifest_text(manifest, entry.display_name).len > 1024 {
            fail(output, path, "display label exceeds generation limit of 1024 bytes");
        }
    }
}

fn identifier(value: u8[:]) -> bool {
    return value.len <= 48 && discovery::import_segment(value);
}

fn valid_path(path: u8[:], kind: discovery::RootKind) -> bool {
    if path.len > 100 || !discovery::test_filename(path) {
        return false;
    }
    if kind == discovery::RootKind.Unit {
        if path.len < 5 || path[..5] != "test/" {
            return false;
        }
    } else if kind == discovery::RootKind.Integration {
        if path.len < 12 || path[..12] != "integration/" {
            return false;
        }
    } else {
        return false;
    }
    let stem = path[..path.len - 6];
    var start: i64 = 0;
    for byte,
    index in stem {
        if byte == '/' {
            if !identifier(stem[start..index]) {
                return false;
            }
            start = index + 1;
        }
    }
    return identifier(stem[start..]);
}

fn import_path(path: u8[:]) -> u8[>..] {
    var result: u8[>..] = [];
    for byte in path[..path.len - 6] {
        result.push(if byte == '/' {
                '.'
            } else {
                byte
            });
    }
    return result;
}
