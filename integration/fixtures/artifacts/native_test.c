// Independent native assertions. Parent supplies and removes an empty temporary directory.
#define _DARWIN_C_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct { const uint8_t *data; int64_t len; } slice;
extern int32_t gt_stage_create(slice, slice);
extern int32_t gt_stage_prepare(int32_t, slice);
extern int32_t gt_stage_write(int32_t, slice, slice);
extern int32_t gt_stage_finish(int32_t, slice);
extern int32_t gt_stage_reset(int32_t, slice, slice);
extern int32_t gt_stage_completion(int32_t, slice, int32_t);

static slice text(const char *value) { return (slice){(const uint8_t *)value, (int64_t)strlen(value)}; }

static void put(int parent, const char *name, const char *value) {
    int fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL, 0600);
    assert(fd >= 0);
    assert(write(fd, value, strlen(value)) == (ssize_t)strlen(value));
    assert(close(fd) == 0);
}

static void unchanged(int fd) {
    struct stat before, after;
    assert(fstatat(fd, "case_0.goose", &before, 0) == 0);
    assert(gt_stage_write(fd, text("case_0.goose"), text("one")) == 0);
    assert(fstatat(fd, "case_0.goose", &after, 0) == 0);
    assert(before.st_ino == after.st_ino);
    assert(before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec);
    assert(before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec);
}

static void interrupted(slice path, int fd) {
    assert(gt_stage_prepare(fd, text("case_0.goose\ncase_1.goose\n")) == 0);
    assert(gt_stage_write(fd, text("case_1.goose"), text("partial")) == 0);
    put(fd, ".write-tmp", "interrupted atomic write");
    assert(close(fd) == 0);
    fd = gt_stage_create(path, text("goosetest_root.goose"));
    assert(fd >= 0);
    assert(faccessat(fd, ".write-tmp", F_OK, 0) < 0 && errno == ENOENT);
    assert(gt_stage_prepare(fd, text("case_0.goose\n")) == 0);
    assert(gt_stage_write(fd, text("case_0.goose"), text("two")) == 0);
    assert(gt_stage_finish(fd, text("case_0.goose\n")) == 0);
    assert(faccessat(fd, "case_1.goose", F_OK, 0) < 0 && errno == ENOENT);
    put(fd, "completion", "0\n");
    assert(gt_stage_completion(fd, text("completion"), 0) == 0);
    assert(gt_stage_completion(fd, text("completion"), 1) < 0);
    assert(gt_stage_reset(fd, text("tests"), text("completion")) == 0);
    assert(gt_stage_completion(fd, text("completion"), 0) < 0);
    assert(close(fd) == 0);
}

static void unsafe_names(slice path) {
    int fd = gt_stage_create(path, text("goosetest_root.goose"));
    assert(fd >= 0);
    put(fd, "case_2.goose", "user-owned");
    assert(gt_stage_prepare(fd, text("case_0.goose\ncase_2.goose\n")) == -EEXIST);
    assert(gt_stage_prepare(fd, text("../escape.goose\n")) < 0);
    assert(gt_stage_prepare(fd, text("case_0.goose\ncase_0.goose\n")) < 0);
    assert(gt_stage_prepare(fd, text("case_0.goose")) < 0);
    assert(linkat(fd, "case_0.goose", fd, "hardlink", 0) == 0);
    assert(gt_stage_prepare(fd, text("case_0.goose\n")) < 0);
    assert(unlinkat(fd, "hardlink", 0) == 0);
    assert(unlinkat(fd, "case_0.goose", 0) == 0);
    assert(symlinkat("case_2.goose", fd, "case_0.goose") == 0);
    assert(gt_stage_prepare(fd, text("case_0.goose\n")) < 0);
    assert(unlinkat(fd, "case_0.goose", 0) == 0);
    assert(unlinkat(fd, ".manifest", 0) == 0);
    put(fd, ".manifest", "../escape.goose\n");
    assert(gt_stage_prepare(fd, text("case_0.goose\n")) < 0);
    assert(unlinkat(fd, ".manifest", 0) == 0);
    put(fd, ".manifest", "case_0.goose\ncase_0.goose\n");
    assert(gt_stage_prepare(fd, text("case_0.goose\n")) < 0);
    int manifest = openat(fd, ".manifest", O_WRONLY);
    assert(manifest >= 0 && ftruncate(manifest, 8388609) == 0);
    assert(close(manifest) == 0);
    assert(gt_stage_prepare(fd, text("case_0.goose\n")) < 0);
    assert(close(fd) == 0);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    int project = open(argv[1], O_RDONLY | O_DIRECTORY);
    assert(project >= 0);
    assert(gt_stage_create(text(argv[1]), text("goosetest_root.goose")) < 0);
    put(project, "goosetest_root.goose", "authored root unchanged");
    int fd = gt_stage_create(text(argv[1]), text("goosetest_root.goose"));
    assert(fd >= 0);
    assert(gt_stage_create(text(argv[1]), text("goosetest_root.goose")) == -EWOULDBLOCK);
    assert(gt_stage_write(fd, text("case_0.goose"), text("one")) < 0);
    assert(gt_stage_prepare(fd, text("case_0.goose\n")) == 0);
    assert(gt_stage_write(fd, text("case_0.goose"), text("one")) == 0);
    assert(gt_stage_write(fd, text("unknown.goose"), text("no")) < 0);
    unchanged(fd);
    assert(gt_stage_finish(fd, text("case_0.goose\n")) == 0);
    interrupted(text(argv[1]), fd);
    unsafe_names(text(argv[1]));
    assert(close(project) == 0);

    char nested_path[4096];
    assert(snprintf(nested_path, sizeof nested_path, "%s/nested", argv[1]) < (int)sizeof nested_path);
    assert(mkdir(nested_path, 0700) == 0);
    int nested_project = open(nested_path, O_RDONLY | O_DIRECTORY);
    assert(nested_project >= 0);
    put(nested_project, "goosetest_core.goose", "authored configured root unchanged");
    assert(close(nested_project) == 0);
    int nested = gt_stage_create(text(nested_path), text("goosetest_core.goose"));
    assert(nested >= 0);
    assert(gt_stage_prepare(nested, text("core/case_0.goose\ncore/runner.goose\ncore/report.goose\ncore/completion.goose\n")) == 0);
    assert(gt_stage_write(nested, text("core/case_0.goose"), text("namespace case;")) == 0);
    assert(gt_stage_write(nested, text("core/report.goose"), text("namespace report;")) == 0);
    assert(gt_stage_write(nested, text("core/completion.goose"), text("namespace completion;")) == 0);
    assert(gt_stage_write(nested, text("core/runner.goose"), text("namespace runner;")) == 0);
    assert(gt_stage_finish(nested, text("core/case_0.goose\ncore/runner.goose\ncore/report.goose\ncore/completion.goose\n")) == 0);
    int core = openat(nested, "core", O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    assert(core >= 0);
    put(core, "completion", "0\n");
    assert(gt_stage_completion(nested, text("core/completion"), 0) == 0);
    assert(gt_stage_reset(nested, text("core/tests"), text("core/completion")) == 0);
    assert(gt_stage_completion(nested, text("core/completion"), 0) < 0);
    assert(gt_stage_prepare(nested, text("core/case_0.goose\ncore/case_1.goose\n")) == 0);
    assert(gt_stage_write(nested, text("core/case_1.goose"), text("partial")) == 0);
    put(core, ".write-tmp", "interrupted nested write");
    assert(close(core) == 0);
    assert(close(nested) == 0);
    nested = gt_stage_create(text(nested_path), text("goosetest_core.goose"));
    assert(nested >= 0);
    assert(gt_stage_prepare(nested, text("core/case_0.goose\n")) == 0);
    core = openat(nested, "core", O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    assert(core >= 0);
    assert(faccessat(core, ".write-tmp", F_OK, 0) < 0 && errno == ENOENT);
    assert(gt_stage_write(nested, text("core/case_0.goose"), text("recovered")) == 0);
    assert(gt_stage_finish(nested, text("core/case_0.goose\n")) == 0);
    assert(faccessat(core, "case_1.goose", F_OK, 0) < 0 && errno == ENOENT);
    assert(close(core) == 0);
    assert(close(nested) == 0);
    puts("native artifact tests passed");
    return 0;
}
