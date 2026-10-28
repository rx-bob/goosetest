// Bounded sorted ownership manifests; publish union before writes for interrupted-run recovery.
#include "staging_internal.h"

typedef struct { uint8_t *bytes; char **names; size_t count; } stage_names;
static stage_names prepared;
static int prepared_fd = -1;
static dev_t prepared_device;
static ino_t prepared_inode;

static void free_names(stage_names *names) {
    free(names->names);
    free(names->bytes);
    memset(names, 0, sizeof *names);
}

static int compare_names(const void *a, const void *b) {
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static int has_name(const stage_names *names, const char *name) {
    return names->count && bsearch(&name, names->names, names->count,
                                   sizeof *names->names, compare_names) != NULL;
}

static int valid_component(const char *name, int target) {
    size_t length = strlen(name);
    if (!length || length > NAME_MAX || name[0] == '.' || name[0] == '-') return 0;
    if (target && !(name[0] >= 'a' && name[0] <= 'z')) return 0;
    for (size_t i = 0; i < length; ++i) {
        unsigned char c = (unsigned char)name[i];
        int alpha = c >= 'a' && c <= 'z';
        int digit = c >= '0' && c <= '9';
        if (target) {
            if (!alpha && !digit && c != '_') return 0;
        } else if (!alpha && !digit && c != '_' && c != '.') return 0;
    }
    return 1;
}

static int valid_leaf(const char *name) {
    if (!valid_component(name, 0)) return 0;
    size_t length = strlen(name);
    return !strcmp(name, "tests") || !strcmp(name, "completion") ||
           (length > 6 && !strcmp(name + length - 6, ".goose"));
}

static int valid_name(const char *name) {
    size_t length = strlen(name);
    if (!length || length > PATH_MAX) return 0;
    const char *slash = strchr(name, '/');
    if (!slash) return valid_leaf(name);
    if (strchr(slash + 1, '/') || slash == name || !slash[1]) return 0;
    char target[NAME_MAX + 1];
    size_t target_length = (size_t)(slash - name);
    if (target_length > NAME_MAX) return 0;
    memcpy(target, name, target_length);
    target[target_length] = 0;
    return valid_component(target, 1) && strcmp(target, "cache") && strcmp(target, "all")
        && valid_leaf(slash + 1);
}

static int target_prefix(const stage_names *names, char *target, size_t capacity, int require_only) {
    target[0] = 0;
    for (size_t i = 0; i < names->count; ++i) {
        const char *slash = strchr(names->names[i], '/');
        if (!slash) {
            if (require_only && target[0]) return EINVAL;
            continue;
        }
        size_t length = (size_t)(slash - names->names[i]);
        if (length + 1 > capacity) return ENAMETOOLONG;
        if (!target[0]) {
            memcpy(target, names->names[i], length);
            target[length] = 0;
        } else if (strlen(target) != length || memcmp(target, names->names[i], length)) {
            return EINVAL;
        }
        if (require_only) {
            for (size_t j = 0; j < names->count; ++j) {
                if (!strchr(names->names[j], '/')) return EINVAL;
            }
        }
    }
    return 0;
}

static int parse_names(gt_stage_slice source, stage_names *names, int reserved) {
    memset(names, 0, sizeof *names);
    if (source.len < 0 || source.len > GT_MANIFEST_LIMIT) return EFBIG;
    if (source.len && (source.data[source.len - 1] != '\n' || memchr(source.data, 0, (size_t)source.len)))
        return EINVAL;
    size_t count = reserved ? 2 : 0;
    for (int64_t i = 0; i < source.len; ++i) if (source.data[i] == '\n') ++count;
    if (count > GT_NAMES_LIMIT) return EFBIG;
    names->bytes = malloc((size_t)source.len + 2 * (NAME_MAX + 16));
    names->names = calloc(count + 1, sizeof *names->names);
    if (!names->bytes || !names->names) { free_names(names); return ENOMEM; }
    if (source.len) memcpy(names->bytes, source.data, (size_t)source.len);
    size_t start = 0;
    for (size_t i = 0; i < (size_t)source.len; ++i) {
        if (names->bytes[i] != '\n') continue;
        names->bytes[i] = 0;
        char *name = (char *)names->bytes + start;
        if (!valid_name(name)) { free_names(names); return EINVAL; }
        names->names[names->count++] = name;
        start = i + 1;
    }
    if (reserved) {
        char target[NAME_MAX + 1];
        int error = target_prefix(names, target, sizeof target, 1);
        if (error) { free_names(names); return error; }
        char *extra = (char *)names->bytes + source.len;
        if (target[0]) {
            size_t length = strlen(target);
            memcpy(extra, target, length);
            extra[length] = '/';
            memcpy(extra + length + 1, "tests\0", 6);
            names->names[names->count++] = extra;
            memcpy(extra + length + 7, target, length);
            extra[length * 2 + 7] = '/';
            memcpy(extra + length * 2 + 8, "completion\0", 11);
            names->names[names->count++] = extra + length + 7;
        } else {
            memcpy(extra, "tests\0completion\0", 17);
            names->names[names->count++] = extra;
            names->names[names->count++] = extra + 6;
        }
    }
    qsort(names->names, names->count, sizeof *names->names, compare_names);
    for (size_t i = 1; i < names->count; ++i) {
        if (!strcmp(names->names[i - 1], names->names[i])) { free_names(names); return EINVAL; }
    }
    return 0;
}

static int load_names(int directory, stage_names *names) {
    uint8_t *bytes = NULL;
    size_t length = 0;
    int error = gt_stage_read(directory, ".manifest", &bytes, &length, GT_MANIFEST_LIMIT);
    if (error == ENOENT) error = 0;
    if (!error) error = parse_names((gt_stage_slice){bytes, (int64_t)length}, names, 0);
    free(bytes);
    return error;
}

static int ensure_target(int directory, const stage_names *names) {
    char target[NAME_MAX + 1];
    int error = target_prefix(names, target, sizeof target, 0);
    if (error || !target[0]) return error;
    char path[NAME_MAX * 2 + 2];
    int length = snprintf(path, sizeof path, "%s/runner.goose", target);
    if (length < 0 || (size_t)length >= sizeof path) return ENAMETOOLONG;
    int fd = -1;
    char leaf[NAME_MAX + 1];
    error = gt_stage_target_open(directory, path, 1, &fd, leaf, sizeof leaf);
    if (!error && fd != directory && close(fd) < 0) error = errno;
    return error;
}

static int nested_stat(int directory, const char *name, struct stat *info, int *exists) {
    int target = -1;
    char leaf[NAME_MAX + 1];
    int error = gt_stage_target_open(directory, name, 0, &target, leaf, sizeof leaf);
    if (error == ENOENT) {
        *exists = 0;
        return 0;
    }
    if (error) return error;
    if (fstatat(target, leaf, info, AT_SYMLINK_NOFOLLOW) < 0) {
        if (errno == ENOENT) *exists = 0;
        else error = errno;
    } else {
        *exists = 1;
    }
    if (target != directory && close(target) < 0 && !error) error = errno;
    return error;
}

static int publish_names(int directory, const stage_names *a, const stage_names *b) {
    uint8_t *bytes = malloc(GT_MANIFEST_LIMIT);
    if (!bytes) return ENOMEM;
    size_t left = 0, right = 0, length = 0, count = 0;
    int error = 0;
    while (left < a->count || right < b->count) {
        int order = left == a->count ? 1 : right == b->count ? -1 :
                    strcmp(a->names[left], b->names[right]);
        const char *name = order <= 0 ? a->names[left++] : b->names[right++];
        if (!order) ++right;
        size_t size = strlen(name);
        if (++count > GT_NAMES_LIMIT || size + 1 > GT_MANIFEST_LIMIT - length) { error = EFBIG; break; }
        memcpy(bytes + length, name, size);
        length += size;
        bytes[length++] = '\n';
    }
    if (!error) error = gt_stage_atomic(directory, ".manifest", (gt_stage_slice){bytes, (int64_t)length});
    free(bytes);
    return error;
}

static int preflight(int directory, const stage_names *old, const stage_names *next) {
    for (size_t i = 0; i < next->count; ++i) {
        struct stat info;
        int exists = 0;
        int error = nested_stat(directory, next->names[i], &info, &exists);
        if (error) return error;
        if (!exists) continue;
        if (!has_name(old, next->names[i])) return EEXIST;
        if (!S_ISREG(info.st_mode) || info.st_nlink != 1) return EINVAL;
    }
    return 0;
}

int32_t gt_stage_prepare(int32_t directory, gt_stage_slice source) {
    free_names(&prepared);
    prepared_fd = -1;
    stage_names old = {0}, next = {0};
    struct stat info;
    int error = fstat(directory, &info) < 0 ? errno : 0;
    if (!error) error = load_names(directory, &old);
    if (!error) error = parse_names(source, &next, 1);
    if (!error) error = ensure_target(directory, &next);
    if (!error) error = preflight(directory, &old, &next);
    if (!error) error = publish_names(directory, &old, &next);
    free_names(&old);
    if (!error) {
        prepared = next;
        prepared_fd = directory;
        prepared_device = info.st_dev;
        prepared_inode = info.st_ino;
    } else free_names(&next);
    return -error;
}

int gt_stage_writable(int directory, const char *name) {
    struct stat info;
    if (fstat(directory, &info) < 0) return errno;
    if (directory != prepared_fd || info.st_dev != prepared_device || info.st_ino != prepared_inode)
        return EINVAL;
    return has_name(&prepared, name) ? 0 : EINVAL;
}

int gt_stage_owned(int directory, const char *name) {
    struct stat info;
    if (fstat(directory, &info) < 0) return errno;
    if (directory == prepared_fd && info.st_dev == prepared_device && info.st_ino == prepared_inode)
        return has_name(&prepared, name) ? 0 : EINVAL;
    int target = -1;
    char leaf[NAME_MAX + 1];
    int error = gt_stage_target_open(directory, name, 0, &target, leaf, sizeof leaf);
    if (error) return error;
    if (target != directory && close(target) < 0) return errno;
    stage_names names = {0};
    error = load_names(directory, &names);
    if (!error && !has_name(&names, name)) error = EINVAL;
    free_names(&names);
    return error;
}

static int in_scope(const char *name, const char *target) {
    const char *slash = strchr(name, '/');
    if (!target[0]) return slash == NULL;
    size_t length = strlen(target);
    return slash == name + length && !memcmp(name, target, length);
}

static int merged_names(const stage_names *old, const stage_names *next, const char *target,
                        stage_names *merged) {
    memset(merged, 0, sizeof *merged);
    size_t retained = 0;
    for (size_t i = 0; i < old->count; ++i)
        if (!in_scope(old->names[i], target)) ++retained;
    if (retained > GT_NAMES_LIMIT - next->count) return EFBIG;
    size_t capacity = retained + next->count;
    merged->names = calloc(capacity + 1, sizeof *merged->names);
    if (!merged->names) return ENOMEM;
    for (size_t i = 0; i < old->count; ++i) {
        if (!in_scope(old->names[i], target)) merged->names[merged->count++] = old->names[i];
    }
    for (size_t i = 0; i < next->count; ++i) merged->names[merged->count++] = next->names[i];
    qsort(merged->names, merged->count, sizeof *merged->names, compare_names);
    for (size_t i = 1; i < merged->count; ++i) {
        if (!strcmp(merged->names[i - 1], merged->names[i])) {
            free(merged->names);
            memset(merged, 0, sizeof *merged);
            return EINVAL;
        }
    }
    return 0;
}

int32_t gt_stage_finish(int32_t directory, gt_stage_slice source) {
    stage_names old = {0}, next = {0}, merged = {0}, empty = {0};
    char target[NAME_MAX + 1];
    int error = load_names(directory, &old);
    if (!error) error = parse_names(source, &next, 1);
    if (!error) error = ensure_target(directory, &next);
    if (!error) error = target_prefix(&next, target, sizeof target, 1);
    if (!error) {
        for (size_t i = 0; i < next.count; ++i) {
            if (!has_name(&old, next.names[i])) { error = EINVAL; break; }
        }
    }
    if (!error) {
        for (size_t i = 0; i < old.count; ++i) {
            if (!in_scope(old.names[i], target) || has_name(&next, old.names[i])) continue;
            error = gt_stage_nested_regular(directory, old.names[i], 1);
            if (error) break;
        }
    }
    if (!error) {
        for (size_t i = 0; i < old.count; ++i) {
            if (!in_scope(old.names[i], target) || has_name(&next, old.names[i])) continue;
            error = gt_stage_nested_remove(directory, old.names[i]);
            if (error) break;
        }
    }
    if (!error) error = merged_names(&old, &next, target, &merged);
    if (!error) error = publish_names(directory, &merged, &empty);
    free_names(&old);
    free_names(&next);
    free(merged.names);
    free_names(&prepared);
    prepared_fd = -1;
    return -error;
}
