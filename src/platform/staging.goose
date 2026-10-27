// Fresh-only artifact ownership; existing directories are never overwritten or removed.
namespace staging;

// Returns an owned directory descriptor or negative POSIX errno. Close via filesystem.
extern "gt_stage_create" fn create(project: const u8[:]) -> i32;
// Exclusive flat file creation, at most 65536 source bytes per file.
extern "gt_stage_write"fn write(fd: i32, name: const u8[:], data: const u8[:]) -> i32;
// Requires exact completion bytes: expected status digit followed by newline.
extern "gt_stage_completion"fn completion(fd: i32, expected: i32) -> i32;
