// Internal bounded artifact operations shared by ownership and manifest adapters.
#ifndef GT_STAGING_INTERNAL_H
#define GT_STAGING_INTERNAL_H
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct { const uint8_t *data; int64_t len; } gt_stage_slice;
enum { GT_INTERRUPTS = 16, GT_SOURCE_LIMIT = 65536, GT_MANIFEST_LIMIT = 8388608,
       GT_NAMES_LIMIT = 140004 };
#define GT_MARKER "goosetest artifacts v1\n"
#define GT_TARGET_MARKER "goosetest target artifacts v1\n"
int gt_stage_path(gt_stage_slice source, char *out, size_t capacity, int child);
int gt_stage_target_open(int directory, const char *name, int create, int *target, char *leaf, size_t leaf_size);
int gt_stage_regular(int directory, const char *name, int missing);
int gt_stage_remove(int directory, const char *name);
int gt_stage_read(int directory, const char *name, uint8_t **out, size_t *length, size_t limit);
int gt_stage_atomic(int directory, const char *name, gt_stage_slice source);
int gt_stage_owned(int directory, const char *name);
int gt_stage_writable(int directory, const char *name);
int gt_stage_verify_entry(int directory, gt_stage_slice entry);
int gt_stage_nested_regular(int directory, const char *name, int missing);
int gt_stage_nested_remove(int directory, const char *name);
int gt_stage_nested_read(int directory, const char *name, uint8_t **out, size_t *length, size_t limit);
#endif
