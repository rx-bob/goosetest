// Complete unit correspondence audit; index records borrow the immutable inventory.
namespace discovery;

import std;

import src.discovery.catalog;
import src.discovery.manifest;
import src.discovery.model;
import src.discovery.paths;

// At most one result per inventory file; matched pairs consume two files.
enum MirrorKind {
    Matched,
    MissingTest,
    OrphanTest,
    BadTestName
}
struct MirrorRecord {
    kind: MirrorKind,
    source_index: i64 = -1,
    test_index: i64 = -1,
}
struct MirrorAudit {
    records: MirrorRecord[>..]&,
    matched: i64 = 0,
    missing: i64 = 0,
    orphaned: i64 = 0,
    bad_names: i64 = 0,
    integration_files: i64 = 0,
    disabled: bool = false,
    complete: bool = false,
}

fn new_mirror_audit(records: MirrorRecord[>..]&) -> MirrorAudit {
    assert(records.len == 0);
    return MirrorAudit {
        records: records,
        ..
    };
}

fn mirror_key(inventory: Inventory&, index: i64) -> const u8[:] {
    let file = inventory.files[index];
    let path = path_text(inventory, file.path);
    if file.root >= 0 {
        let root = inventory.roots[file.root];
        let root_path = path_text(inventory, root.path);
        let relative = path[root_path.len + 1..];
        if file.kind == RootKind.Source {
            return relative[..relative.len - 6];
        }
        return relative[..relative.len - 11];
    }
    if file.kind == RootKind.Source {
        return path[4..path.len - 6];
    }
    return path[5..path.len - 11];
}

fn audit_mirrors(audit: MirrorAudit&, inventory: Inventory&) {
    assert(!audit.complete);
    assert(audit.records.len == 0);
    if status(inventory) != 0 {
        return;
    }
    if inventory.mirror_disabled {
        audit.disabled = true;
        audit.complete = true;
        for file in inventory.files {
            if file.kind == RootKind.Integration {
                audit.integration_files += 1;
            }
        }
        return;
    }
    var sources: i64[>..] = [];
    var tests: i64[>..] = [];
    for file,
    index in inventory.files {
        if file.kind == RootKind.Source {
            if !inventory.configured || file.pair >= 0 {
                sources.push(index);
            }
        } else if !test_filename(path_text(inventory, file.path)) {
            if !inventory.configured {
                audit.records.push(MirrorRecord {
                        kind: MirrorKind.BadTestName,
                        test_index: index,
                        ..
                    });
                audit.bad_names += 1;
            }
        } else if file.kind == RootKind.Unit {
            if !inventory.configured || file.pair >= 0 {
                tests.push(index);
            }
        } else {
            audit.integration_files += 1;
        }
    }
    sort(sources) {
        a,
        b => mirror_less(inventory, a, b)
    };
    sort(tests) {
        a,
        b => mirror_less(inventory, a, b)
    };
    merge_mirrors(audit, inventory, sources, tests);
    audit.complete = true;
    assert(audit.records.len <= inventory.files.len);
}

fn merge_mirrors(audit: MirrorAudit&, inventory: Inventory&, sources: i64[:], tests: i64[:]) {
    var source: i64 = 0;
    var test: i64 = 0;
    while source < sources.len || test < tests.len {
        if source == sources.len {
            record_orphan(audit, tests[test]);
            test += 1;
        } else if test == tests.len {
            record_missing(audit, sources[source]);
            source += 1;
        } else {
            let left = mirror_key(inventory, sources[source]);
            let right = mirror_key(inventory, tests[test]);
            let source_pair = inventory.files[sources[source]].pair;
            let test_pair = inventory.files[tests[test]].pair;
            if source_pair == test_pair && left == right {
                audit.records.push(MirrorRecord {
                        kind: MirrorKind.Matched,
                        source_index: sources[source],
                        test_index: tests[test]
                    });
                audit.matched += 1;
                source += 1;
                test += 1;
            } else if source_pair < test_pair || (source_pair == test_pair && bytewise_less(left, right)) {
                record_missing(audit, sources[source]);
                source += 1;
            } else {
                record_orphan(audit, tests[test]);
                test += 1;
            }
        }
    }
}

fn record_missing(audit: MirrorAudit&, index: i64) {
    audit.records.push(MirrorRecord {
            kind: MirrorKind.MissingTest,
            source_index: index,
            ..
        });
    audit.missing += 1;
}

fn record_orphan(audit: MirrorAudit&, index: i64) {
    audit.records.push(MirrorRecord {
            kind: MirrorKind.OrphanTest,
            test_index: index,
            ..
        });
    audit.orphaned += 1;
}

fn mirror_status(audit: MirrorAudit&) -> i32 {
    if audit.complete && !audit.disabled && audit.missing == 0 && audit.orphaned == 0 && audit.bad_names == 0 {
        return 0;
    }
    return 2;
}

fn mirror_valid(audit: MirrorAudit&) -> bool {
    return audit.complete && (audit.disabled || mirror_status(audit) == 0);
}

fn mirror_less(inventory: Inventory&, left: i64, right: i64) -> bool {
    let left_pair = inventory.files[left].pair;
    let right_pair = inventory.files[right].pair;
    if left_pair != right_pair {
        return left_pair < right_pair;
    }
    return bytewise_less(mirror_key(inventory, left), mirror_key(inventory, right));
}

fn mirror_record_text(inventory: Inventory&, record: MirrorRecord) -> u8[>..] {
    if record.kind == MirrorKind.MissingTest {
        let path = path_text(inventory, inventory.files[record.source_index].path);
        return str("MISSING TEST  ", path, "\n              expected ", expected_counterpart(inventory,
            inventory.files[record.source_index], RootKind.Unit, mirror_key(inventory, record.source_index), true));
    }
    let path = path_text(inventory, inventory.files[record.test_index].path);
    if record.kind == MirrorKind.OrphanTest {
        return str("ORPHAN TEST  ", path, "\n             expected ", expected_counterpart(inventory,
            inventory.files[record.test_index], RootKind.Source, mirror_key(inventory, record.test_index), false));
    }
    if record.kind == MirrorKind.BadTestName {
        return str("BAD TEST NAME  ", path, ": expected *_test.goose; move helpers to test_support/");
    }
    return str("MIRROR OK  ", path_text(inventory, inventory.files[record.source_index].path), " -> ", path);
}

fn expected_counterpart(inventory: Inventory&, file: SourceFile, kind: RootKind, key: u8[:], test: bool) -> u8[>..] {
    if file.root >= 0 {
        for root in inventory.roots {
            if root.pair == file.pair && root.kind == kind {
                let suffix = if test {
                    "_test.goose"
                } else {
                    ".goose"
                };
                return str(path_text(inventory, root.path), "/", key, suffix);
            }
        }
    }
    if test {
        return str("test/", key, "_test.goose");
    }
    return str("src/", key, ".goose");
}

// All layout and syntax validation precedes any future selection stage.
fn inspect_project(audit: MirrorAudit&, manifest: Manifest&, inventory: Inventory&) {
    audit_mirrors(audit, inventory);
    if inventory.configured || mirror_status(audit) == 0 {
        discover(manifest, inventory);
    }
    if manifest_status(manifest) == 0 && manifest.cases.len == 0 {
        let path = if inventory.configured && inventory.roots.len > 0 {
            path_text(inventory, inventory.roots[0].path)
        } else {
            "test/"
        };
        syntax_fail(manifest, path, SourceLocation {
            }, SyntaxIssue.NoCases);
    }
}

fn project_status(audit: MirrorAudit&, manifest: Manifest&) -> i32 {
    if mirror_valid(audit) && manifest_status(manifest) == 0 {
        return 0;
    }
    return 2;
}
