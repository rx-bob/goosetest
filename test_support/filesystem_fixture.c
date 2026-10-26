// Test-only mutation helpers. Production filesystem adapter remains read-only.
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct { const uint8_t *data; int64_t len; } gt_test_slice;

static int copy_path(gt_test_slice path, char out[PATH_MAX]) {
    if (path.len <= 0 || path.len >= PATH_MAX) return EINVAL;
    if (memchr(path.data, 0, (size_t)path.len)) return EINVAL;
    memcpy(out, path.data, (size_t)path.len);
    out[path.len] = 0;
    return 0;
}

int32_t gt_test_symlink(gt_test_slice target, gt_test_slice path) {
    char source[PATH_MAX], destination[PATH_MAX];
    int error = copy_path(target, source);
    if (!error) error = copy_path(path, destination);
    if (error) return -error;
    return symlink(source, destination) < 0 ? -errno : 0;
}

int32_t gt_test_chmod(gt_test_slice path, int32_t mode) {
    char name[PATH_MAX];
    int error = copy_path(path, name);
    if (error) return -error;
    return chmod(name, (mode_t)mode) < 0 ? -errno : 0;
}

int32_t gt_test_unprivileged(void) { return geteuid() != 0; }

int64_t gt_test_fd_count(void) {
    // Standalone test process starts with only stdio; depth is bounded far below 4096.
    int64_t count = 0;
    for (int fd = 0; fd < 4096; ++fd) {
        if (fcntl(fd, F_GETFD) >= 0) ++count;
    }
    return count;
}
