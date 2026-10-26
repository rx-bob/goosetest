// Owns mirror records for bounded independent audit checks.
namespace mirror_support;

import src.discovery.mirror;
import src.discovery.model;

fn with_audit<F>() {
    var records: discovery::MirrorRecord[>..] = [];
    var audit = discovery::new_mirror_audit(records);
    F(audit);
}

fn add(inventory: discovery::Inventory&, path: u8[:], kind: discovery::RootKind, source: u8[:] = "") {
    let file = discovery::SourceFile {
        path: discovery::Span {
            offset: inventory.paths.len,
            length: path.len
        },
        source: discovery::Span {
            offset: inventory.sources.len,
            length: source.len
        },
        kind: kind
    };
    inventory.paths.append(path);
    inventory.sources.append(source);
    inventory.files.push(file);
}
