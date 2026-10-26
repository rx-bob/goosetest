// Inventory-to-manifest coordination and sorted duplicate validation, independent of mirror auditing.
namespace discovery;

import std;

import src.discovery.declarations;
import src.discovery.manifest;
import src.discovery.model;
import src.discovery.paths;

struct IdentityIndex {
    text: Span,
    index: i64
}

fn discover(manifest: Manifest&, inventory: Inventory&) {
    assert(manifest.suites.len == 0);
    if status(inventory) != 0 {
        syntax_fail(manifest, inventory.error_path, SourceLocation {
            }, SyntaxIssue.IncompleteInventory);
        return;
    }
    for file,
    index in inventory.files {
        let path = path_text(inventory, file.path);
        if file.kind != RootKind.Source {
            if !test_filename(path) {
                syntax_fail(manifest, path, SourceLocation {
                    }, SyntaxIssue.BadTestFilename);
                return;
            }
            parse_file(manifest, path, source_text(inventory, file), file.kind, index);
            if manifest.error.issue == SyntaxIssue.None {
                let suite = manifest.suites[manifest.suites.len - 1];
                if suite.case_count == 0 {
                    syntax_fail(manifest, path, suite.namespace_location, SyntaxIssue.EmptySuite);
                }
            }
        }
        if manifest.error.issue != SyntaxIssue.None {
            return;
        }
    }
    finish_manifest(manifest);
}

fn finish_manifest(manifest: Manifest&) {
    if manifest.error.issue != SyntaxIssue.None {
        return;
    }
    var cases: IdentityIndex[>..] = [];
    for entry,
    index in manifest.cases {
        cases.push(IdentityIndex {
                text: entry.identity,
                index: index
            });
    }
    sort(cases) {
        a,
        b => identity_less(manifest, a, b)
    };
    for index in 0..cases.len {
        if index == 0 {
            continue;
        }
        if manifest_text(manifest, cases[index - 1].text) == manifest_text(manifest, cases[index].text) {
            let entry = manifest.cases[cases[index].index];
            let suite = manifest.suites[entry.suite_index];
            syntax_fail(manifest, manifest_text(manifest, suite.path), entry.location, SyntaxIssue.DuplicateCase);
            return;
        }
    }
    validate_namespaces(manifest);
    if manifest.error.issue == SyntaxIssue.None {
        manifest.complete = true;
    }
}

fn validate_namespaces(manifest: Manifest&) {
    var suites: IdentityIndex[>..] = [];
    for suite,
    index in manifest.suites {
        suites.push(IdentityIndex {
                text: suite.namespace_name,
                index: index
            });
    }
    sort(suites) {
        a,
        b => identity_less(manifest, a, b)
    };
    for index in 0..suites.len {
        if index == 0 {
            continue;
        }
        if manifest_text(manifest, suites[index - 1].text) == manifest_text(manifest, suites[index].text) {
            let suite = manifest.suites[suites[index].index];
            syntax_fail(manifest, manifest_text(manifest, suite.path), suite.namespace_location,
                SyntaxIssue.SuiteCollision);
            return;
        }
    }
}

fn identity_less(manifest: Manifest&, a: IdentityIndex, b: IdentityIndex) -> bool {
    let left = manifest_text(manifest, a.text);
    let right = manifest_text(manifest, b.text);
    if left == right {
        return a.index < b.index;
    }
    return bytewise_less(left, right);
}
