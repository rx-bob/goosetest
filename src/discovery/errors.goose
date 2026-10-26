// Structured errors retain the offending path, limit value, and native errno.
namespace discovery;

import std;

import src.discovery.model;

fn error_name(error: Error) -> const u8[:] {
    match error {
        None => {
            return "scan not completed";
        },
        InvalidLimits => {
            return "limits must be nonnegative";
        },
        OpenProject => {
            return "cannot open project directory";
        },
        MissingRoot => {
            return "required root is missing";
        },
        RootNotDirectory => {
            return "scan root must be a directory";
        },
        InspectEntry => {
            return "cannot inspect directory entry";
        },
        ListDirectory => {
            return "cannot list directory";
        },
        OpenDirectory => {
            return "cannot open directory without following links";
        },
        ReadSource => {
            return "cannot read regular source file without following links";
        },
        CloseDirectory => {
            return "cannot close directory";
        },
        CloseProject => {
            return "cannot close project directory";
        },
        Symlink => {
            return "symlinks are not allowed under scan roots";
        },
        UnsupportedKind => {
            return "entry is not a regular file or directory";
        },
        InvalidImport => {
            return "path segment is not a Goose import identifier";
        },
        EntryLimit => {
            return "max_entries exceeded";
        },
        DepthLimit => {
            return "max_depth exceeded";
        },
        PathLimit => {
            return "max_path_bytes exceeded";
        },
        PathStorageLimit => {
            return "max_path_storage_bytes exceeded";
        },
        FileSizeLimit => {
            return "max_file_bytes exceeded";
        },
        SourceSizeLimit => {
            return "max_source_bytes exceeded";
        },
    }
}

fn error_text(inventory: Inventory&) -> u8[>..] {
    var text: u8[>..] = [];
    format(text, inventory.error_path, ": ", error_name(inventory.error));
    if inventory.limit >= 0 {
        format(text, " (limit ", inventory.limit, ")");
    }
    if inventory.system_error > 0 {
        format(text, " (errno ", inventory.system_error, ")");
    }
    return text;
}
