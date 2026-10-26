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
    source_index: i64 = - 1,
    test_index: i64 = - 1,
}
struct MirrorAudit {
    records: MirrorRecord[>..]&,
    matched: i64 = 0,
    missing: i64 = 0,
    orphaned: i64 = 0,
    bad_names: i64 = 0,
    integration_files: i64 = 0,
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
    if file.kind == RootKind.Source {
        return path[4..path.len - 6];
    }
    return path[5..path.len - 11];
}

fn audit_mirrors(audit: MirrorAudit&, inventory: Inventory&) {
    assert( !audit.complete && audit.records.len == 0);
    if status(inventory) != 0 {
        return;
    }
    var sources: i64[>..] = [];
    var tests: i64[>..] = [];
    for file,
    index in inventory.files {
        if file.kind == RootKind.Source {
            sources.push(index);
        } else if !test_filename(path_text(inventory, file.path)) {
            audit.records.push(MirrorRecord {
                    kind: MirrorKind.BadTestName,
                    test_index: index,
                    ..
                });
            audit.bad_names += 1;
        } else if file.kind == RootKind.Unit {
            tests.push(index);
        } else {
            audit.integration_files += 1;
        }
    }
    sort(sources) {
        a,
        b => bytewise_less(mirror_key(inventory, a), mirror_key(inventory, b))
    };
    sort(tests) {
        a,
        b => bytewise_less(mirror_key(inventory, a), mirror_key(inventory, b))
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
            if left == right {
                audit.records.push(MirrorRecord {
                        kind: MirrorKind.Matched,
                        source_index: sources[source],
                        test_index: tests[test]
                    });
                audit.matched += 1;
                source += 1;
                test += 1;
            } else if bytewise_less(left, right) {
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
    if audit.complete && audit.missing == 0 && audit.orphaned == 0 && audit.bad_names == 0 {
        return 0;
    }
    return 2;
}

fn mirror_record_text(inventory: Inventory&, record: MirrorRecord) -> u8[>..] {
    if record.kind == MirrorKind.MissingTest {
        let path = path_text(inventory, inventory.files[record.source_index].path);
        return str("MISSING TEST  ", path, "\n              expected test/",
            mirror_key(inventory, record.source_index), "_test.goose");
    }
    let path = path_text(inventory, inventory.files[record.test_index].path);
    if record.kind == MirrorKind.OrphanTest {
        return str("ORPHAN TEST  ", path, "\n             expected src/",
            mirror_key(inventory, record.test_index), ".goose");
    }
    if record.kind == MirrorKind.BadTestName {
        return str("BAD TEST NAME  ", path, ": expected *_test.goose; move helpers to test_support/");
    }
    return str("MIRROR OK  ", path_text(inventory, inventory.files[record.source_index].path), " -> ", path);
}

// All layout and syntax validation precedes any future selection stage.
fn inspect_project(audit: MirrorAudit&, manifest: Manifest&, inventory: Inventory&) {
    audit_mirrors(audit, inventory);
    if mirror_status(audit) != 0 {
        return;
    }
    discover(manifest, inventory);
    if manifest_status(manifest) == 0 && manifest.cases.len == 0 {
        syntax_fail(manifest, "test/", SourceLocation {
            }, SyntaxIssue.NoCases);
    }
}

fn project_status(audit: MirrorAudit&, manifest: Manifest&) -> i32 {
    if mirror_status(audit) == 0 && manifest_status(manifest) == 0 {
        return 0;
    }
    return 2;
}
