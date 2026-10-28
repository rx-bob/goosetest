// Iterative depth-first inventory holds one directory handle per depth and sorts files once.
namespace discovery;

import std;

import src.config.model;
import src.discovery.model;
import src.discovery.paths;
import src.platform.filesystem;

struct DirectoryFrame {
    handle: i64,
    path: Span,
    depth: i64,
    root: i64 = -1,
    target: i64 = -1,
}

struct ConfiguredRoot {
    name: const u8[:],
    kind: RootKind,
    target: i64,
    pair: i64,
}

fn scan(inventory: Inventory&, project: u8[:]) {
    assert(!inventory.started);
    inventory.started = true;
    if inventory.error != Error.None {
        return;
    }
    let fd = filesystem::open_project(project);
    if fd < 0 {
        fail(inventory, Error.OpenProject, project, -(fd as i64));
        return;
    }
    scan_root(inventory, fd, "src", RootKind.Source, 0);
    scan_root(inventory, fd, "test", RootKind.Unit, 0);
    scan_root(inventory, fd, "integration", RootKind.Integration, -1);
    let closed = filesystem::close_project(fd);
    if closed < 0 {
        fail(inventory, Error.CloseProject, project, -(closed as i64));
    }
    if inventory.error != Error.None {
        return;
    }
    sort(inventory.files) {
        left,
        right =>
        bytewise_less(path_text(inventory, left.path), path_text(inventory, right.path))
    };
    inventory.complete = true;
}

fn scan_configured(inventory: Inventory&, project: u8[:], configuration: config::Configuration&) {
    assert(!inventory.started);
    assert(configuration.configured);
    inventory.started = true;
    inventory.configured = true;
    inventory.mirror_disabled = true;
    if inventory.error != Error.None {
        return;
    }
    copy_exclusions(inventory, configuration);
    if inventory.error != Error.None {
        return;
    }
    let fd = filesystem::open_project(project);
    if fd < 0 {
        fail(inventory, Error.OpenProject, project, -(fd as i64));
        return;
    }
    for target_index in 0..configuration.targets.len {
        scan_configured_target(inventory, fd, configuration, target_index);
    }
    let closed = filesystem::close_project(fd);
    if closed < 0 {
        fail(inventory, Error.CloseProject, project, -(closed as i64));
    }
    if inventory.error != Error.None {
        return;
    }
    sort(inventory.files) {
        left,
        right => bytewise_less(path_text(inventory, left.path), path_text(inventory, right.path))
    };
    inventory.complete = true;
}

fn copy_exclusions(inventory: Inventory&, configuration: config::Configuration&) {
    for target_index in 0..configuration.targets.len {
        let target = configuration.targets[target_index];
        for index in target.exclusion_start..target.exclusion_start + target.exclusion_count {
            let item = configuration.exclusions[index];
            let path = config::text_value(configuration, item.path);
            let normalized = if item.directory {
                path[..path.len - 1]
            } else {
                path
            };
            let span = Span {
                offset: inventory.paths.len,
                length: normalized.len
            };
            inventory.paths.append(normalized);
            inventory.exclusions.push(ExclusionRule {
                    path: span,
                    target: target_index,
                    directory: item.directory,
                });
        }
        if target.policy == config::MirrorPolicy.Strict {
            inventory.mirror_disabled = false;
        }
    }
}

fn scan_configured_target(
    inventory: Inventory&, fd: i32, configuration: config::Configuration&, target_index: i64
) {
    let target = configuration.targets[target_index];
    for index in target.root_start..target.root_start + target.root_count {
        let root = configuration.roots[index];
        let kind = if root.kind == config::TestKind.Unit {
            RootKind.Unit
        } else {
            RootKind.Integration
        };
        let pair = if root.kind == config::TestKind.Unit && target.policy == config::MirrorPolicy.Strict {
            pair_for_root(configuration, target, root.path)
        } else {
            -1
        };
        scan_configured_root(inventory, fd, ConfiguredRoot {
                name: config::text_value(configuration, root.path),
                kind: kind,
                target: target_index,
                pair: pair,
            });
    }
    if target.policy == config::MirrorPolicy.Strict {
        for index in target.pair_start..target.pair_start + target.pair_count {
            let pair = configuration.pairs[index];
            scan_configured_root(inventory, fd, ConfiguredRoot {
                    name: config::text_value(configuration, pair.source),
                    kind: RootKind.Source,
                    target: target_index,
                    pair: index,
                });
        }
    }
}

fn pair_for_root(configuration: config::Configuration&, target: config::Target, root: config::Span) -> i64 {
    let root_path = config::text_value(configuration, root);
    for index in target.pair_start..target.pair_start + target.pair_count {
        let pair = configuration.pairs[index];
        if config::text_value(configuration, pair.tests) == root_path {
            return index;
        }
    }
    return -1;
}

fn scan_configured_root(inventory: Inventory&, fd: i32, root_request: ConfiguredRoot) {
    if inventory.error != Error.None {
        return;
    }
    let handle = open_directory_path(inventory, fd, root_request.name);
    if handle <= 0 {
        return;
    }
    let path = record_path(inventory, root_request.name, 0);
    if inventory.error != Error.None {
        close_if_open(inventory, handle, root_request.name);
        return;
    }
    let root = inventory.roots.len;
    inventory.roots.push(RootRecord {
            path: path,
            kind: root_request.kind,
            target: root_request.target,
            pair: root_request.pair
        });
    var stack: DirectoryFrame[>..<] = [];
    stack.push(DirectoryFrame {
            handle: handle,
            path: path,
            depth: 0,
            root: root,
            target: root_request.target
        });
    walk(inventory, stack);
    close_stack(inventory, stack);
}

fn open_directory_path(inventory: Inventory&, project_fd: i32, path: u8[:]) -> i64 {
    var start: i64 = 0;
    var parent = project_fd;
    var previous: i64 = 0;
    while start < path.len {
        var end = start;
        while end < path.len && path[end] != '/' {
            end += 1;
        }
        let segment = path[start..end];
        let entry = filesystem::kind(parent, segment);
        if filesystem::missing(entry) != 0 {
            fail(inventory, Error.MissingRoot, path, -(entry as i64));
            close_if_open(inventory, previous, path);
            return 0;
        }
        if entry < 0 {
            fail(inventory, Error.InspectEntry, path, -(entry as i64));
            close_if_open(inventory, previous, path);
            return 0;
        }
        if entry == filesystem::SYMLINK {
            fail(inventory, Error.Symlink, path);
            close_if_open(inventory, previous, path);
            return 0;
        }
        if entry != filesystem::DIRECTORY {
            fail(inventory, Error.RootNotDirectory, path);
            close_if_open(inventory, previous, path);
            return 0;
        }
        let next = filesystem::open_directory(parent, segment);
        if next < 0 {
            fail(inventory, Error.OpenDirectory, path, -next);
            close_if_open(inventory, previous, path);
            return 0;
        }
        close_if_open(inventory, previous, path);
        if inventory.error != Error.None {
            close_if_open(inventory, next, path);
            return 0;
        }
        previous = next;
        parent = filesystem::directory_fd(next);
        if parent < 0 {
            fail(inventory, Error.OpenDirectory, path, -parent);
            close_if_open(inventory, previous, path);
            return 0;
        }
        start = end + 1;
    }
    return previous;
}

fn close_if_open(inventory: Inventory&, handle: i64, path: u8[:]) {
    if handle > 0 {
        let result = filesystem::close_directory(handle);
        if result < 0 {
            fail(inventory, Error.CloseDirectory, path, -result);
        }
    }
}

fn is_excluded(inventory: Inventory&, target: i64, path: u8[:]) -> bool {
    for rule in inventory.exclusions {
        if rule.target != target {
            continue;
        }
        let prefix = path_text(inventory, rule.path);
        if !rule.directory && prefix == path {
            return true;
        }
        if rule.directory && (path == prefix || (path.len > prefix.len && path[..prefix.len] == prefix
            && path[prefix.len] == '/')) {
            return true;
        }
    }
    return false;
}

fn scan_root(inventory: Inventory&, fd: i32, name: u8[:], kind: RootKind, pair: i64) {
    if inventory.error != Error.None {
        return;
    }
    let entry = filesystem::kind(fd, name);
    if filesystem::missing(entry) != 0 {
        if kind != RootKind.Integration {
            fail(inventory, Error.MissingRoot, name, -(entry as i64));
        }
        return;
    }
    if entry < 0 {
        fail(inventory, Error.InspectEntry, name, -(entry as i64));
        return;
    }
    if entry == filesystem::SYMLINK {
        fail(inventory, Error.Symlink, name);
        return;
    }
    if entry != filesystem::DIRECTORY {
        fail(inventory, Error.RootNotDirectory, name);
        return;
    }
    let path = record_path(inventory, name, 0);
    if inventory.error != Error.None {
        return;
    }
    let root = inventory.roots.len;
    inventory.roots.push(RootRecord {
            path: path,
            kind: kind,
            target: -1,
            pair: pair
        });
    let handle = filesystem::open_directory(fd, name);
    if handle < 0 {
        fail(inventory, Error.OpenDirectory, name, -handle);
        return;
    }
    var stack: DirectoryFrame[>..<] = [];
    stack.push(DirectoryFrame {
            handle: handle,
            path: path,
            depth: 0,
            root: root,
            target: -1,
        });
    walk(inventory, stack);
    close_stack(inventory, stack);
}

fn walk(inventory: Inventory&, stack: DirectoryFrame[>..<]&) {
    // Every non-EOF iteration consumes a budgeted entry; EOF pops a bounded frame.
    while stack.len > 0 && inventory.error == Error.None {
        let frame = stack[stack.len - 1];
        var name: u8[>..] = [];
        let entry = filesystem::next(frame.handle, name);
        if entry == 0 {
            close_top(inventory, stack);
            continue;
        }
        let path = join_path(path_text(inventory, frame.path), name);
        if entry < 0 {
            let error = if name.len == 0 {
                Error.ListDirectory
            } else {
                Error.InspectEntry
            };
            let offending = if name.len == 0 {
                path_text(inventory, frame.path)
            } else {
                path[..]
            };
            fail(inventory, error, offending, -(entry as i64));
            return;
        }
        visit(inventory, stack, name, entry, path);
    }
}

fn visit(inventory: Inventory&, stack: DirectoryFrame[>..<]&, name: u8[:], entry: i32, path: u8[:]) {
    let frame = stack[stack.len - 1];
    let depth = if entry == filesystem::DIRECTORY {
        frame.depth + 1
    } else {
        frame.depth
    };
    let stored = record_path(inventory, path, depth);
    if inventory.error != Error.None {
        return;
    }
    if is_excluded(inventory, frame.target, path) {
        return;
    }
    let root_kind = inventory.roots[frame.root].kind;
    if inventory.configured && entry == filesystem::FILE && root_kind != RootKind.Source && !test_filename(name) {
        return;
    }
    if inventory.configured && entry == filesystem::SYMLINK
        && root_kind != RootKind.Source && !test_filename(name) && !goose_file(name) {
        return;
    }
    if entry == filesystem::SYMLINK {
        fail(inventory, Error.Symlink, path);
        return;
    }
    if entry == filesystem::OTHER {
        fail(inventory, Error.UnsupportedKind, path);
        return;
    }
    let parent = filesystem::directory_fd(frame.handle);
    if entry == filesystem::DIRECTORY {
        descend(inventory, stack, parent, name, DirectoryFrame {
                handle: 0,
                path: stored,
                depth: depth,
                root: frame.root,
                target: frame.target,
            });
    } else if goose_file(name) && (root_kind == RootKind.Source || !inventory.configured || test_filename(name)) {
        if !import_segment(name[..name.len - 6]) {
            fail(inventory, Error.InvalidImport, path);
            return;
        }
        read_source(inventory, parent, name, stored, root_kind, frame.root);
    }
}

fn descend(inventory: Inventory&, stack: DirectoryFrame[>..<]&, parent: i32, name: u8[:], frame: DirectoryFrame) {
    let path = path_text(inventory, frame.path);
    if !import_segment(name) {
        fail(inventory, Error.InvalidImport, path);
        return;
    }
    let handle = filesystem::open_directory(parent, name);
    if handle < 0 {
        fail(inventory, Error.OpenDirectory, path, -handle);
        return;
    }
    stack.push(DirectoryFrame {
            handle: handle,
            path: frame.path,
            depth: frame.depth,
            root: frame.root,
            target: frame.target,
        });
}

fn read_source(inventory: Inventory&, parent: i32, name: u8[:], path: Span, kind: RootKind, root: i64) {
    let remaining = inventory.limits.max_source_bytes - inventory.sources.len;
    let budget = if remaining < inventory.limits.max_file_bytes {
        remaining
    } else {
        inventory.limits.max_file_bytes
    };
    var source: u8[>..] = [];
    let result = filesystem::read(parent, name, source, budget);
    if result == filesystem::READ_LIMIT {
        let error = if remaining < inventory.limits.max_file_bytes {
            Error.SourceSizeLimit
        } else {
            Error.FileSizeLimit
        };
        let limit = if error == Error.FileSizeLimit {
            inventory.limits.max_file_bytes
        } else {
            inventory.limits.max_source_bytes
        };
        fail(inventory, error, path_text(inventory, path), 0, limit);
    } else if result < 0 {
        fail(inventory, Error.ReadSource, path_text(inventory, path), -(result as i64));
    } else {
        let contents = Span {
            offset: inventory.sources.len,
            length: source.len
        };
        inventory.sources.append(source);
        inventory.files.push(SourceFile {
                path: path,
                source: contents,
                kind: kind,
                root: root,
                pair: inventory.roots[root].pair,
            });
    }
}

fn close_top(inventory: Inventory&, stack: DirectoryFrame[>..<]&) {
    let frame = stack.pop();
    let result = filesystem::close_directory(frame.handle);
    if result < 0 {
        fail(inventory, Error.CloseDirectory, path_text(inventory, frame.path), -(result as i64));
    }
}

fn close_stack(inventory: Inventory&, stack: DirectoryFrame[>..<]&) {
    // Cleanup consumes exactly the remaining bounded stack, even after the first error.
    while stack.len > 0 {
        close_top(inventory, stack);
    }
}
