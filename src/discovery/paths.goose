// Importable segments use pinned compiler identifiers; relative paths are built with forward slashes.
namespace discovery;

import src.discovery.model;

let KEYWORDS: const u8[:][45] = [
    "import", "namespace", "struct", "enum", "type", "fn", "thread_fn", "export", "simd",
    "recursive", "let", "var", "extern", "const", "pad", "reusable", "if", "else", "while",
    "for", "in", "loop", "block", "guard", "match", "return", "break", "continue", "as",
    "true", "false", "null", "self", "bool", "varint", "i8", "i16", "i32", "i64",
    "u8", "u16", "u32", "u64", "f32", "f64",
];

fn identifier_start(byte: u8) -> bool {
    return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || byte == '_';
}

fn import_segment(name: u8[:]) -> bool {
    if name.len == 0 {
        return false;
    }
    if !identifier_start(name[0]) {
        return false;
    }
    for byte in name {
        if !identifier_start(byte) && !(byte >= '0' && byte <= '9') {
            return false;
        }
    }
    for keyword in KEYWORDS {
        if name == keyword {
            return false;
        }
    }
    return true;
}

fn goose_file(name: u8[:]) -> bool {
    return name.len >= 6 && name[name.len - 6..] == ".goose";
}

fn join_path(parent: u8[:], name: u8[:]) -> u8[>..] {
    var path: u8[>..] = [];
    path.append(parent);
    if parent.len > 0 {
        path.push('/');
    }
    path.append(name);
    return path;
}

fn bytewise_less(left: u8[:], right: u8[:]) -> bool {
    let length = if left.len < right.len {
        left.len
    } else {
        right.len
    };
    for index in 0..length {
        if left[index] != right[index] {
            return left[index] < right[index];
        }
    }
    return left.len < right.len;
}

fn record_path(inventory: Inventory&, path: u8[:], depth: i64) -> Span {
    if inventory.visited_entries >= inventory.limits.max_entries {
        fail(inventory, Error.EntryLimit, path, 0, inventory.limits.max_entries);
    } else if depth > inventory.limits.max_depth {
        fail(inventory, Error.DepthLimit, path, 0, inventory.limits.max_depth);
    } else if path.len > inventory.limits.max_path_bytes {
        fail(inventory, Error.PathLimit, path, 0, inventory.limits.max_path_bytes);
    } else if path.len > inventory.limits.max_path_storage_bytes - inventory.paths.len {
        fail(inventory, Error.PathStorageLimit, path, 0, inventory.limits.max_path_storage_bytes);
    }
    if inventory.error != Error.None {
        return Span {
        };
    }
    let span = Span {
        offset: inventory.paths.len,
        length: path.len
    };
    inventory.paths.append(path);
    inventory.visited_entries += 1;
    return span;
}

// Both test roots admit only named suites; helpers belong outside these roots.
fn test_filename(path: u8[:]) -> bool {
    if path.len <= 11 || path[path.len - 11..] != "_test.goose" {
        return false;
    }
    return path[path.len - 12] != '/';
}
