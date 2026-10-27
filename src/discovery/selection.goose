// Selection is a literal stable-ID predicate; callers still validate the complete manifest.
namespace selection;

import std;

import src.discovery.manifest;
import src.discovery.model;

enum Suite {
    All,
    Unit,
    Integration
}
struct Options {
    filter: const u8[:] = "",
    suite: Suite = Suite.All,
}

fn matches(manifest: discovery::Manifest&, entry: discovery::Case, options: Options = Options {
    }) -> bool {
    let kind = manifest.suites[entry.suite_index].kind;
    if kind != discovery::RootKind.Unit && kind != discovery::RootKind.Integration {
        return false;
    }
    if options.suite == Suite.Unit && kind != discovery::RootKind.Unit {
        return false;
    }
    if options.suite == Suite.Integration && kind != discovery::RootKind.Integration {
        return false;
    }
    return find(discovery::manifest_text(manifest, entry.identity), options.filter) >= 0;
}

fn count(manifest: discovery::Manifest&, options: Options = Options {
    }) -> i64 {
    var selected: i64 = 0;
    for entry in manifest.cases {
        if matches(manifest, entry, options) {
            selected += 1;
        }
    }
    return selected;
}
