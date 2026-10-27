// Fresh-only descriptor-relative artifacts. Never overwrite or remove existing paths.
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct { const uint8_t *data; int64_t len; } gt_stage_slice;
enum { GT_STAGE_INTERRUPTS = 16, GT_STAGE_SOURCE_LIMIT = 65536 };

static int stage_path(gt_stage_slice source, char *out, size_t capacity, int child) {
    if (source.len <= 0) return EINVAL;
    if ((uint64_t)source.len >= capacity) return ENAMETOOLONG;
    if (memchr(source.data, 0, (size_t)source.len)) return EINVAL;
    memcpy(out, source.data, (size_t)source.len);
    out[source.len] = 0;
    if (child && (strchr(out, '/') || !strcmp(out, ".") || !strcmp(out, ".."))) return EINVAL;
    return 0;
}

static int check_root(int project) {
    int fd = openat(project, "goosetest_root.goose", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return errno;
    struct stat info;
    int error = 0;
    if (fstat(fd, &info) < 0) error = errno;
    else if (!S_ISREG(info.st_mode)) error = EINVAL;
    if (close(fd) < 0 && !error) error = errno;
    return error;
}

int32_t gt_stage_create(gt_stage_slice path) {
    char name[PATH_MAX];
    int error = stage_path(path, name, sizeof name, 0);
    if (error) return -error;
    int project = open(name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (project < 0) return -errno;
    error = check_root(project);
    int output = -1;
    if (!error && mkdirat(project, "goosetest_generated", 0700) < 0) error = errno;
    if (!error) {
        output = openat(project, "goosetest_generated", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (output < 0) error = errno;
    }
    if (close(project) < 0 && !error) error = errno;
    if (error && output >= 0) close(output);
    return error ? -error : output;
}

static int write_source(int fd, gt_stage_slice source) {
    int64_t offset = 0;
    int interrupts = 0;
    while (offset < source.len) {
        ssize_t count = write(fd, source.data + offset, (size_t)(source.len - offset));
        if (count < 0) {
            if (errno == EINTR && ++interrupts <= GT_STAGE_INTERRUPTS) continue;
            return errno;
        }
        if (count == 0) return EIO;
        offset += count;
    }
    return 0;
}

int32_t gt_stage_write(int32_t directory, gt_stage_slice name, gt_stage_slice source) {
    char path[NAME_MAX + 1];
    int error = stage_path(name, path, sizeof path, 1);
    if (error) return -error;
    if (source.len < 0 || source.len > GT_STAGE_SOURCE_LIMIT) return -EINVAL;
    int fd = openat(directory, path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return -errno;
    error = write_source(fd, source);
    if (close(fd) < 0 && !error) error = errno;
    return -error;
}

static int read_completion(int fd, int32_t expected) {
    struct stat info;
    if (fstat(fd, &info) < 0) return errno;
    if (!S_ISREG(info.st_mode) || info.st_size != 2) return EINVAL;
    uint8_t bytes[3];
    size_t used = 0;
    int interrupts = 0;
    while (used < sizeof bytes) {
        ssize_t count = read(fd, bytes + used, sizeof bytes - used);
        if (count < 0) {
            if (errno == EINTR && ++interrupts <= GT_STAGE_INTERRUPTS) continue;
            return errno;
        }
        if (!count) break;
        used += (size_t)count;
    }
    return used == 2 && bytes[0] == '0' + expected && bytes[1] == '\n' ? 0 : EINVAL;
}

int32_t gt_stage_completion(int32_t directory, int32_t expected) {
    if (expected < 0 || expected > 2) return -EINVAL;
    int fd = openat(directory, "completion", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return -errno;
    int error = read_completion(fd, expected);
    if (close(fd) < 0 && !error) error = errno;
    return -error;
}
