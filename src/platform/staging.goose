// Locked artifact ownership. Single-threaded CLI keeps one prepared generation at a time.
namespace staging;

// Returns an exclusively locked directory descriptor or negative POSIX errno. Close via filesystem.
extern "gt_stage_create" fn create_native(project: const u8[:], entry: const u8[:]) -> i32;

fn create(project: const u8[:], entry: const u8[:] = "goosetest_root.goose") -> i32 {
    return create_native(project, entry);
}

// Claim a bounded newline-delimited list before writes; interrupted claims remain recoverable.
extern "gt_stage_prepare" fn prepare(fd: i32, names: const u8[:]) -> i32;

// Atomic compare/write, at most 65536 source bytes; name must have been prepared.
extern "gt_stage_write" fn write(fd: i32, name: const u8[:], data: const u8[:]) -> i32;

// Prune only previously claimed files absent from the new list, then commit the list.
extern "gt_stage_finish" fn finish(fd: i32, names: const u8[:]) -> i32;

// Remove owned binary/completion before building, so old success can never be reused.
extern "gt_stage_reset" fn reset_native(fd: i32, binary: const u8[:], completion: const u8[:]) -> i32;

fn reset(fd: i32, binary: const u8[:] = "tests", completion: const u8[:] = "completion") -> i32 {
    return reset_native(fd, binary, completion);
}

// Requires exact completion bytes: expected status digit followed by newline.
extern "gt_stage_completion" fn completion_native(fd: i32, path: const u8[:], expected: i32) -> i32;

fn completion(fd: i32, expected: i32) -> i32 {
    return completion_native(fd, "completion", expected);
}

fn completion_at(fd: i32, path: const u8[:], expected: i32) -> i32 {
    return completion_native(fd, path, expected);
}
