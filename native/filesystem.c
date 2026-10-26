// Read-only descriptor-relative filesystem boundary; every child open rejects links.
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include "goose.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct { const uint8_t *data; int64_t len; } gt_fs_slice;
enum { GT_FILE = 1, GT_DIRECTORY = 2, GT_LINK = 3, GT_OTHER = 4 };
enum { GT_READ_LIMIT = 1000001, GT_INTERRUPTS = 16 };

static int copy_path(gt_fs_slice source, char *out, size_t capacity, int child) {
    if (source.len <= 0) return EINVAL;
    if ((uint64_t)source.len >= capacity) return ENAMETOOLONG;
    if (memchr(source.data, 0, (size_t)source.len)) return EINVAL;
    memcpy(out, source.data, (size_t)source.len);
    out[source.len] = 0;
    if (child && (strchr(out, '/') || !strcmp(out, ".") || !strcmp(out, ".."))) return EINVAL;
    return 0;
}

int32_t gt_fs_open_project(gt_fs_slice path) {
    char name[PATH_MAX];
    int error = copy_path(path, name, sizeof name, 0);
    if (error) return -error;
    int fd = open(name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    return fd < 0 ? -errno : fd;
}

int32_t gt_fs_close_project(int32_t fd) {
    return close(fd) < 0 ? -errno : 0;
}

static int32_t kind_at(int fd, const char *name) {
    struct stat info;
    if (fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) < 0) return -errno;
    if (S_ISREG(info.st_mode)) return GT_FILE;
    if (S_ISDIR(info.st_mode)) return GT_DIRECTORY;
    if (S_ISLNK(info.st_mode)) return GT_LINK;
    return GT_OTHER;
}

int32_t gt_fs_kind(int32_t fd, gt_fs_slice path) {
    char name[NAME_MAX + 1];
    int error = copy_path(path, name, sizeof name, 1);
    return error ? -error : kind_at(fd, name);
}

int64_t gt_fs_open_directory(int32_t parent, gt_fs_slice path) {
    char name[NAME_MAX + 1];
    int error = copy_path(path, name, sizeof name, 1);
    if (error) return -error;
    int fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -errno;
    DIR *directory = fdopendir(fd);
    if (!directory) {
        error = errno;
        close(fd);
        return -error;
    }
    return (int64_t)(intptr_t)directory;
}

int32_t gt_fs_directory_fd(int64_t handle) {
    if (handle <= 0) return -EBADF;
    int fd = dirfd((DIR *)(intptr_t)handle);
    return fd < 0 ? -errno : fd;
}

int32_t gt_fs_next(int64_t handle, gs_rref name) {
    if (handle <= 0) return -EBADF;
    DIR *directory = (DIR *)(intptr_t)handle;
    // A directory contains at most two dot entries; no delimiter encoding is used.
    for (int attempt = 0; attempt < 3; ++attempt) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) return errno ? -errno : 0;
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t length = strnlen(entry->d_name, NAME_MAX + 1);
        if (length > NAME_MAX) return -ENAMETOOLONG;
        gs_bld_append(name, entry->d_name, (int64_t)length);
        return kind_at(dirfd(directory), entry->d_name);
    }
    return -EIO;
}

int32_t gt_fs_close_directory(int64_t handle) {
    if (handle <= 0) return -EBADF;
    return closedir((DIR *)(intptr_t)handle) < 0 ? -errno : 0;
}

static int32_t read_bounded(int fd, gs_rref out, int64_t budget) {
    uint8_t buffer[4096];
    int64_t used = 0;
    int interrupts = 0;
    // Each successful iteration consumes bytes; EOF or budget + one probe ends it.
    while (used <= budget) {
        int64_t remaining = budget - used;
        size_t request = remaining >= (int64_t)sizeof buffer ? sizeof buffer : (size_t)remaining + 1;
        ssize_t count = read(fd, buffer, request);
        if (count < 0) {
            if (errno == EINTR && ++interrupts <= GT_INTERRUPTS) continue;
            return -errno;
        }
        if (count == 0) return 0;
        if (count > remaining) return -GT_READ_LIMIT;
        gs_bld_append(out, buffer, count);
        used += count;
    }
    return -GT_READ_LIMIT;
}

int32_t gt_fs_read(int32_t parent, gt_fs_slice path, gs_rref out, int64_t budget) {
    char name[NAME_MAX + 1];
    int error = copy_path(path, name, sizeof name, 1);
    if (error || budget < 0) return -(error ? error : EINVAL);
    int fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return -errno;
    struct stat info;
    int32_t result = 0;
    if (fstat(fd, &info) < 0) result = -errno;
    else if (!S_ISREG(info.st_mode)) result = -EINVAL;
    else if (info.st_size > budget) result = -GT_READ_LIMIT;
    else result = read_bounded(fd, out, budget);
    if (close(fd) < 0 && result == 0) result = -errno;
    return result;
}

int32_t gt_fs_missing(int32_t result) { return result == -ENOENT; }
