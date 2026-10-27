// Locked, descriptor-relative artifact ownership. No recursive removal or authored-root writes.
#include "staging_internal.h"
#include <sys/file.h>

int gt_stage_path(gt_stage_slice source, char *out, size_t capacity, int child) {
    if (source.len <= 0) return EINVAL;
    if ((uint64_t)source.len >= capacity) return ENAMETOOLONG;
    if (memchr(source.data, 0, (size_t)source.len)) return EINVAL;
    memcpy(out, source.data, (size_t)source.len);
    out[source.len] = 0;
    if (child && (strchr(out, '/') || !strcmp(out, ".") || !strcmp(out, ".."))) return EINVAL;
    return 0;
}

int gt_stage_regular(int directory, const char *name, int missing) {
    struct stat info;
    if (fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) < 0)
        return missing && errno == ENOENT ? 0 : errno;
    return S_ISREG(info.st_mode) && info.st_nlink == 1 ? 0 : EINVAL;
}

int gt_stage_remove(int directory, const char *name) {
    int error = gt_stage_regular(directory, name, 1);
    if (!error && unlinkat(directory, name, 0) < 0 && errno != ENOENT) error = errno;
    return error;
}

static int read_bytes(int fd, uint8_t *bytes, size_t size) {
    size_t used = 0;
    int interrupts = 0;
    while (used < size) {
        ssize_t count = read(fd, bytes + used, size - used);
        if (count < 0) {
            if (errno == EINTR && ++interrupts <= GT_INTERRUPTS) continue;
            return errno;
        }
        if (!count) return EIO;
        used += (size_t)count;
    }
    uint8_t tail;
    ssize_t count = read(fd, &tail, 1);
    return count == 0 ? 0 : count < 0 ? errno : EFBIG;
}

int gt_stage_read(int directory, const char *name, uint8_t **out, size_t *length, size_t limit) {
    *out = NULL;
    *length = 0;
    int fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return errno;
    struct stat info;
    int error = 0;
    if (fstat(fd, &info) < 0) error = errno;
    else if (!S_ISREG(info.st_mode) || info.st_nlink != 1) error = EINVAL;
    else if (info.st_size < 0 || (uint64_t)info.st_size > limit) error = EFBIG;
    if (!error) {
        *out = malloc((size_t)info.st_size + 1);
        if (!*out) error = ENOMEM;
        else {
            *length = (size_t)info.st_size;
            error = read_bytes(fd, *out, *length);
            (*out)[*length] = 0;
        }
    }
    if (close(fd) < 0 && !error) error = errno;
    if (error) { free(*out); *out = NULL; *length = 0; }
    return error;
}

static int write_bytes(int fd, gt_stage_slice source) {
    int64_t offset = 0;
    int interrupts = 0;
    while (offset < source.len) {
        ssize_t count = write(fd, source.data + offset, (size_t)(source.len - offset));
        if (count < 0) {
            if (errno == EINTR && ++interrupts <= GT_INTERRUPTS) continue;
            return errno;
        }
        if (!count) return EIO;
        offset += count;
    }
    return 0;
}

int gt_stage_atomic(int directory, const char *name, gt_stage_slice source) {
    uint8_t *old = NULL;
    size_t length = 0;
    int error = gt_stage_read(directory, name, &old, &length, GT_MANIFEST_LIMIT);
    if (!error && length == (size_t)source.len && !memcmp(old, source.data, length)) {
        free(old);
        return 0;
    }
    free(old);
    if (error && error != ENOENT) return error;
    int fd = openat(directory, ".write-tmp", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return errno;
    error = write_bytes(fd, source);
    if (!error && fsync(fd) < 0) error = errno;
    if (close(fd) < 0 && !error) error = errno;
    if (!error && renameat(directory, ".write-tmp", directory, name) < 0) error = errno;
    if (error) gt_stage_remove(directory, ".write-tmp");
    return error;
}

static int initialize(int output, int fresh) {
    if (flock(output, LOCK_EX | LOCK_NB) < 0) return errno;
    if (fresh) {
        int fd = openat(output, ".owner", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd < 0) return errno;
        gt_stage_slice marker = {(const uint8_t *)GT_MARKER, sizeof(GT_MARKER) - 1};
        int error = write_bytes(fd, marker);
        if (!error && fsync(fd) < 0) error = errno;
        if (close(fd) < 0 && !error) error = errno;
        if (error) return error;
    }
    uint8_t *marker = NULL;
    size_t length = 0;
    int error = gt_stage_read(output, ".owner", &marker, &length, sizeof(GT_MARKER));
    if (!error && (length != sizeof(GT_MARKER) - 1 || memcmp(marker, GT_MARKER, length))) error = EINVAL;
    free(marker);
    if (!error) error = gt_stage_remove(output, ".write-tmp");
    return error;
}

int32_t gt_stage_create(gt_stage_slice path) {
    char name[PATH_MAX];
    int error = gt_stage_path(path, name, sizeof name, 0);
    if (error) return -error;
    int project = open(name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (project < 0) return -errno;
    error = flock(project, LOCK_EX | LOCK_NB) < 0 ? errno : 0;
    if (!error) error = gt_stage_regular(project, "goosetest_root.goose", 0);
    int fresh = 0, output = -1;
    if (!error) {
        if (mkdirat(project, "goosetest_generated", 0700) == 0) fresh = 1;
        else if (errno != EEXIST) error = errno;
    }
    if (!error) {
        output = openat(project, "goosetest_generated", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (output < 0) error = errno;
        else error = initialize(output, fresh);
    }
    if (close(project) < 0 && !error) error = errno;
    if (error && output >= 0) close(output);
    return error ? -error : output;
}

int32_t gt_stage_write(int32_t directory, gt_stage_slice name, gt_stage_slice source) {
    char path[NAME_MAX + 1];
    int error = gt_stage_path(name, path, sizeof path, 1);
    if (error) return -error;
    if (source.len < 0 || source.len > GT_SOURCE_LIMIT) return -EINVAL;
    error = gt_stage_writable(directory, path);
    if (!error) error = gt_stage_atomic(directory, path, source);
    return -error;
}

int32_t gt_stage_reset(int32_t directory) {
    int error = gt_stage_owned(directory, "tests");
    if (!error) error = gt_stage_owned(directory, "completion");
    if (!error) error = gt_stage_regular(directory, "tests", 1);
    if (!error) error = gt_stage_regular(directory, "completion", 1);
    if (!error) error = gt_stage_remove(directory, "tests");
    if (!error) error = gt_stage_remove(directory, "completion");
    return -error;
}

int32_t gt_stage_completion(int32_t directory, int32_t expected) {
    if (expected < 0 || expected > 2) return -EINVAL;
    uint8_t *bytes = NULL;
    size_t length = 0;
    int error = gt_stage_read(directory, "completion", &bytes, &length, 2);
    if (!error && (length != 2 || bytes[0] != '0' + expected || bytes[1] != '\n')) error = EINVAL;
    free(bytes);
    return -error;
}
