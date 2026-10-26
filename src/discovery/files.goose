// Iterative depth-first inventory holds one directory handle per depth and sorts files once.
namespace discovery;

import std;

import src.discovery.model;
import src.discovery.paths;
import src.platform.filesystem;

struct DirectoryFrame {
    handle: i64,
    path: Span,
    depth: i64
}

fn scan(inventory: Inventory&, project: u8[:]) {
    assert( !inventory.started);
    inventory.started = true;
    if inventory.error != Error.None {
        return;
    }
    let fd = filesystem::open_project(project);
    if fd < 0 {
        fail(inventory, Error.OpenProject, project, -(fd as i64));
        return;
    }
    scan_root(inventory, fd, "src", RootKind.Source);
    scan_root(inventory, fd, "test", RootKind.Unit);
    scan_root(inventory, fd, "integration", RootKind.Integration);
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

fn scan_root(inventory: Inventory&, fd: i32, name: u8[:], kind: RootKind) {
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
    let handle = filesystem::open_directory(fd, name);
    if handle < 0 {
        fail(inventory, Error.OpenDirectory, name, - handle);
        return;
    }
    var stack: DirectoryFrame[>..<] = [];
    stack.push(DirectoryFrame {
            handle: handle,
            path: path,
            depth: 0
        });
    walk(inventory, stack, kind);
    close_stack(inventory, stack);
}

fn walk(inventory: Inventory&, stack: DirectoryFrame[>..<]&, kind: RootKind) {
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
        visit(inventory, stack, name, entry, path, kind);
    }
}

fn visit(
    inventory: Inventory&, stack: DirectoryFrame[>..<]&, name: u8[:], entry: i32, path: u8[:], kind: RootKind
) {
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
                depth: depth
            });
    } else if goose_file(name) {
        if !import_segment(name[..name.len - 6]) {
            fail(inventory, Error.InvalidImport, path);
            return;
        }
        read_source(inventory, parent, name, stored, kind);
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
        fail(inventory, Error.OpenDirectory, path, - handle);
        return;
    }
    stack.push(DirectoryFrame {
            handle: handle,
            path: frame.path,
            depth: frame.depth
        });
}

fn read_source(inventory: Inventory&, parent: i32, name: u8[:], path: Span, kind: RootKind) {
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
                kind: kind
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
