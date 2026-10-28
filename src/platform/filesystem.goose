// Canonical read-only native declarations. Negative results preserve POSIX errno.
namespace filesystem;

let FILE = 1;
let DIRECTORY = 2;
let SYMLINK = 3;
let OTHER = 4;
let READ_LIMIT = -1000001;

extern "gt_fs_open_project" fn open_project(path: const u8[:]) -> i32;

extern "gt_fs_close_project" fn close_project(fd: i32) -> i32;

extern "gt_fs_kind" fn kind(fd: i32, name: const u8[:]) -> i32;

// Directory handles own one descriptor and must be closed exactly once.
extern "gt_fs_open_directory" fn open_directory(parent: i32, name: const u8[:]) -> i64;

extern "gt_fs_directory_fd" fn directory_fd(handle: i64) -> i32;

// Appends one raw name; 0 means EOF, positive means kind, negative means error.
extern "gt_fs_next" fn next(handle: i64, name: u8[>..]&) -> i32;

extern "gt_fs_close_directory" fn close_directory(handle: i64) -> i32;

// Appends at most budget bytes. Callers discard scratch on any nonzero result.
extern "gt_fs_read" fn read(parent: i32, name: const u8[:], out: u8[>..]&, budget: i64) -> i32;

extern "gt_fs_missing" fn missing(result: i32) -> i32;
