// Only this process's mkdtemp result can be removed; no caller-provided deletion paths.
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct { uint8_t *data; int64_t len; } gt_selfhost_slice;
static char owned_root[PATH_MAX];
static int owned_fd = -1;
static dev_t owned_device;
static ino_t owned_inode;
enum { MAX_DEPTH = 64, MAX_ENTRIES = 100000 };

int32_t gt_selfhost_prepare(void) {
    if (owned_fd >= 0 || owned_root[0]) return EALREADY;
    const char *parent = getenv("TMPDIR");
    if (!parent || !parent[0]) parent = "/tmp";
    int length = snprintf(owned_root, sizeof owned_root, "%s/goosetest-selfhost-XXXXXX", parent);
    if (length < 0 || (size_t)length >= sizeof owned_root) {
        owned_root[0] = 0;
        return ENAMETOOLONG;
    }
    if (!mkdtemp(owned_root)) { int error = errno; owned_root[0] = 0; return error; }
    owned_fd = open(owned_root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat info;
    if (owned_fd < 0 || fstat(owned_fd, &info) < 0) {
        int error = errno;
        if (owned_fd >= 0) close(owned_fd);
        owned_fd = -1;
        rmdir(owned_root);
        owned_root[0] = 0;
        return error;
    }
    owned_device = info.st_dev;
    owned_inode = info.st_ino;
    return 0;
}

int64_t gt_selfhost_root_length(void) {
    size_t length = strlen(owned_root);
    if (owned_fd < 0) return -1;
    return (int64_t)length;
}

int32_t gt_selfhost_root_byte(int64_t index) {
    size_t length = strlen(owned_root);
    if (owned_fd < 0 || index < 0 || (uint64_t)index >= length) return -1;
    return (unsigned char)owned_root[index];
}

static int remove_contents(int fd, unsigned depth, unsigned *entries);

static int remove_entry(int parent, const char *name, unsigned depth, unsigned *entries) {
    struct stat info;
    if (++*entries > MAX_ENTRIES) return E2BIG;
    if (fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) < 0) return errno;
    if (!S_ISDIR(info.st_mode)) return unlinkat(parent, name, 0) < 0 ? errno : 0;
    // Fixtures deliberately chmod directories unreadable. Do not follow links while restoring access.
    if (fchmodat(parent, name, 0700, AT_SYMLINK_NOFOLLOW) < 0) return errno;
    int child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (child < 0) return errno;
    struct stat actual;
    int error = fstat(child, &actual) < 0 ? errno : 0;
    if (!error && (actual.st_dev != info.st_dev || actual.st_ino != info.st_ino)) error = ESTALE;
    if (!error) error = remove_contents(child, depth + 1, entries);
    close(child);
    if (!error && unlinkat(parent, name, AT_REMOVEDIR) < 0) error = errno;
    return error;
}

static int remove_contents(int fd, unsigned depth, unsigned *entries) {
    if (depth > MAX_DEPTH) return E2BIG;
    if (fchmod(fd, 0700) < 0) return errno;
    int copy = dup(fd);
    if (copy < 0) return errno;
    DIR *directory = fdopendir(copy);
    if (!directory) { int error = errno; close(copy); return error; }
    int error = 0;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) { error = errno; break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        error = remove_entry(fd, entry->d_name, depth, entries);
        if (error) break;
    }
    if (closedir(directory) < 0 && !error) error = errno;
    return error;
}

int32_t gt_selfhost_cleanup(void) {
    if (owned_fd < 0) return owned_root[0] ? EINVAL : 0;
    unsigned entries = 0;
    int error = remove_contents(owned_fd, 0, &entries);
    struct stat current;
    if (!error && lstat(owned_root, &current) < 0) error = errno;
    if (!error && (current.st_dev != owned_device || current.st_ino != owned_inode)) error = ESTALE;
    if (!error && rmdir(owned_root) < 0) error = errno;
    if (close(owned_fd) < 0 && !error) error = errno;
    owned_fd = -1;
    owned_root[0] = 0;
    return error;
}
