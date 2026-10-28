// Independent test-only observers; production process externs remain canonical.
namespace process_support;

extern "gt_test_process_reaped" fn reaped(pid: i64) -> i32;

extern "gt_test_process_begin" fn begin() -> i32;

extern "gt_test_process_end" fn end() -> i32;

extern "gt_test_process_home_save" fn home_save() -> i32;

extern "gt_test_process_home_unchanged" fn home_unchanged() -> i32;
