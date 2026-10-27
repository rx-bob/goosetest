// Synchronous macOS stage ownership: direct argv, explicit cwd, bounded group termination.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <sys/proc.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>

#if !defined(__APPLE__) || !defined(__aarch64__)
#error "goosetest process adapter currently supports macOS arm64 only"
#endif

extern char **environ;
typedef struct { const uint8_t *data; int64_t len; } gt_process_slice;
typedef struct {
    int64_t kind, exit_code, signal, error, pid, reaped, cleanup_error;
} gt_process_result;
enum { GT_EXIT, GT_LAUNCH, GT_SIGNAL, GT_CANCEL, GT_DEADLINE, GT_SYSTEM, GT_INVALID };
enum { GT_ARG_COUNT = 256, GT_ARG_BYTES = 65536, GT_CWD_BYTES = 4096, GT_POLL_MS = 10 };
enum { GT_SPAWN_CANCEL = -1, GT_SPAWN_DEADLINE = -2 };
static volatile sig_atomic_t cancelled;
// This API is deliberately serial and single-threaded; handlers belong to the CLI stage.
static int active;

struct signal_scope {
    sigset_t old_mask, blocked;
    struct sigaction old_int, old_term;
    int mask_saved, int_saved, term_saved;
};

static void on_cancel(int number) {
    if (!cancelled) cancelled = number;
}

static int64_t now_ms(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) < 0) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int begin_signals(struct signal_scope *scope) {
    sigemptyset(&scope->blocked);
    sigaddset(&scope->blocked, SIGINT);
    sigaddset(&scope->blocked, SIGTERM);
    sigaddset(&scope->blocked, SIGCHLD);
    struct sigaction child_action;
    if (sigaction(SIGCHLD, NULL, &child_action) < 0) return errno;
    if (child_action.sa_handler == SIG_IGN || (child_action.sa_flags & SA_NOCLDWAIT)) return EINVAL;
    if (sigprocmask(SIG_BLOCK, &scope->blocked, &scope->old_mask) < 0) return errno;
    scope->mask_saved = 1;
    struct sigaction action = {0};
    action.sa_handler = on_cancel;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGINT, &action, &scope->old_int) < 0) return errno;
    scope->int_saved = 1;
    if (sigaction(SIGTERM, &action, &scope->old_term) < 0) return errno;
    scope->term_saved = 1;
    return 0;
}

static int end_signals(struct signal_scope *scope) {
    int error = 0;
    if (scope->mask_saved && sigprocmask(SIG_BLOCK, &scope->blocked, NULL) < 0) error = errno;
    if (scope->term_saved && sigaction(SIGTERM, &scope->old_term, NULL) < 0 && !error) error = errno;
    if (scope->int_saved && sigaction(SIGINT, &scope->old_int, NULL) < 0 && !error) error = errno;
    if (scope->mask_saved && sigprocmask(SIG_SETMASK, &scope->old_mask, NULL) < 0 && !error) error = errno;
    return error;
}

static int unpack(gt_process_slice packed, gt_process_slice cwd, char **argv,
                  char *bytes, char *directory) {
    if (packed.len <= 1 || packed.len > GT_ARG_BYTES || cwd.len <= 0 || cwd.len > GT_CWD_BYTES)
        return EINVAL;
    if (packed.data[packed.len - 1] || !packed.data[0] || memchr(cwd.data, 0, (size_t)cwd.len))
        return EINVAL;
    memcpy(bytes, packed.data, (size_t)packed.len);
    memcpy(directory, cwd.data, (size_t)cwd.len);
    directory[cwd.len] = 0;
    size_t offset = 0, count = 0;
    while (offset < (size_t)packed.len) {
        if (count == GT_ARG_COUNT) return E2BIG;
        argv[count++] = bytes + offset;
        offset += strlen(bytes + offset) + 1;
    }
    argv[count] = NULL;
    return 0;
}

// Setup masks cancellation; observe pending signals without launching another candidate.
static int launch_budget(int64_t end) {
    sigset_t pending;
    if (sigpending(&pending) < 0) return errno;
    if (sigismember(&pending, SIGINT)) cancelled = SIGINT;
    else if (sigismember(&pending, SIGTERM)) cancelled = SIGTERM;
    if (cancelled) return GT_SPAWN_CANCEL;
    int64_t now = now_ms();
    if (now < 0) return errno;
    return now >= end ? GT_SPAWN_DEADLINE : 0;
}

// Search PATH ourselves: Darwin posix_spawnp has an implicit /bin/sh fallback.
static int spawn_direct(pid_t *pid, char **argv, posix_spawn_file_actions_t *actions,
                        posix_spawnattr_t *attributes, int64_t end_time) {
    int budget = launch_budget(end_time);
    if (budget) return budget;
    if (strchr(argv[0], '/')) return posix_spawn(pid, argv[0], actions, attributes, argv, environ);
    const char *path = getenv("PATH");
    if (!path) path = "/usr/bin:/bin";
    size_t length = strnlen(path, GT_ARG_BYTES + 1);
    if (length > GT_ARG_BYTES) return E2BIG;
    size_t name_length = strlen(argv[0]);
    size_t start = 0;
    int denied = 0;
    for (size_t end = 0; end <= length; ++end) {
        if (end != length && path[end] != ':') continue;
        budget = launch_budget(end_time);
        if (budget) return budget;
        size_t segment = end - start;
        if (segment + (segment != 0) + name_length > GT_CWD_BYTES) return ENAMETOOLONG;
        char candidate[GT_CWD_BYTES + 1];
        memcpy(candidate, path + start, segment);
        size_t offset = segment;
        if (segment) candidate[offset++] = '/';
        memcpy(candidate + offset, argv[0], name_length + 1);
        int error = posix_spawn(pid, candidate, actions, attributes, argv, environ);
        if (error == EACCES) denied = 1;
        else if (error != ENOENT && error != ENOTDIR) return error;
        start = end + 1;
    }
    return denied ? EACCES : ENOENT;
}

static int spawn_stage(pid_t *pid, char **argv, const char *cwd, int64_t end) {
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_t actions;
    int error = posix_spawnattr_init(&attributes);
    if (error) return error;
    error = posix_spawn_file_actions_init(&actions);
    if (error) { posix_spawnattr_destroy(&attributes); return error; }
    sigset_t mask, defaults;
    sigemptyset(&mask);
    sigemptyset(&defaults);
    int signals[] = {SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE};
    for (size_t i = 0; i < sizeof signals / sizeof *signals; ++i) sigaddset(&defaults, signals[i]);
    if (!error) error = posix_spawnattr_setsigmask(&attributes, &mask);
    if (!error) error = posix_spawnattr_setsigdefault(&attributes, &defaults);
    if (!error) error = posix_spawnattr_setpgroup(&attributes, 0);
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        | POSIX_SPAWN_CLOEXEC_DEFAULT;
    if (!error) error = posix_spawnattr_setflags(&attributes, flags);
    if (!error) error = posix_spawn_file_actions_addchdir_np(&actions, cwd);
    for (int fd = 0; fd < 3 && !error; ++fd) {
        if (fcntl(fd, F_GETFD) >= 0) error = posix_spawn_file_actions_addinherit_np(&actions, fd);
        else if (errno != EBADF) error = errno;
    }
    if (!error) error = spawn_direct(pid, argv, &actions, &attributes, end);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    if (error) *pid = 0;
    return error;
}

// Darwin reports EPERM for a group containing only unreaped zombies. Verify that
// condition rather than hiding a genuine permissions failure on a live member.
static int group_is_dead(pid_t group) {
    enum { CAPACITY = 4096 };
    struct kinfo_proc *members = calloc(CAPACITY, sizeof *members);
    if (!members) return 0;
    size_t bytes = CAPACITY * sizeof *members;
    int query[] = {CTL_KERN, KERN_PROC, KERN_PROC_PGRP, group};
    int valid = sysctl(query, 4, members, &bytes, NULL, 0) == 0
        && bytes < CAPACITY * sizeof *members && bytes % sizeof *members == 0;
    int leader = 0;
    if (valid) {
        for (size_t i = 0; i < bytes / sizeof *members; ++i) {
            if (members[i].kp_proc.p_pid == group) leader = 1;
            if (members[i].kp_eproc.e_pgid != group || members[i].kp_proc.p_stat != SZOMB) valid = 0;
        }
    }
    free(members);
    return valid && leader;
}

static void signal_group(pid_t pid, int number, gt_process_result *result) {
    if (kill(-pid, number) == 0 || errno == ESRCH) return;
    int error = errno;
    if (error == EPERM && group_is_dead(pid)) return;
    if (!result->cleanup_error) result->cleanup_error = error;
}

static void pause_poll(void) {
    struct timespec delay = {0, GT_POLL_MS * 1000000};
    nanosleep(&delay, NULL);
}

static void reap(pid_t pid, gt_process_result *result) {
    int status;
    pid_t waited;
    do { waited = waitpid(pid, &status, 0); } while (waited < 0 && errno == EINTR);
    if (waited < 0) {
        if (!result->cleanup_error) result->cleanup_error = errno;
        return;
    }
    result->reaped = 1;
    if (result->kind == GT_EXIT) {
        if (WIFEXITED(status)) result->exit_code = WEXITSTATUS(status);
        else if (WIFSIGNALED(status)) {
            result->kind = GT_SIGNAL;
            result->signal = WTERMSIG(status);
        } else { result->kind = GT_SYSTEM; result->error = ECHILD; }
    }
}

static void supervise(pid_t pid, int64_t end, int64_t grace, gt_process_result *result) {
    for (;;) {
        int64_t now = now_ms();
        if (cancelled) { result->kind = GT_CANCEL; result->signal = cancelled; break; }
        if (now < 0) { result->kind = GT_SYSTEM; result->error = errno; break; }
        if (now >= end) { result->kind = GT_DEADLINE; break; }
        siginfo_t info = {0};
        // Keep the leader waitable until final group cleanup: its PID cannot be reused.
        if (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOHANG | WNOWAIT) < 0) {
            if (errno == EINTR) continue;
            result->kind = GT_SYSTEM; result->error = errno; break;
        }
        if (info.si_pid == pid) { result->kind = GT_EXIT; break; }
        pause_poll();
    }
    if (result->kind != GT_EXIT) {
        signal_group(pid, result->kind == GT_CANCEL ? (int)result->signal : SIGTERM, result);
        int64_t now = now_ms();
        int64_t until = now < 0 ? 0 : now + grace;
        while (now >= 0 && now < until) { pause_poll(); now = now_ms(); }
    }
    // Also remove lingering group members after a normally exited stage leader.
    signal_group(pid, SIGKILL, result);
    reap(pid, result);
    if (cancelled) { result->kind = GT_CANCEL; result->signal = cancelled; result->exit_code = -1; }
}

void gt_process_run(gt_process_slice packed, gt_process_slice cwd, int64_t deadline,
                    int64_t grace, gt_process_result *result) {
    *result = (gt_process_result){GT_INVALID, -1, 0, 0, 0, 0, 0};
    if (deadline <= 0 || deadline > 86400000 || grace < 0 || grace > 60000) return;
    if (active) { result->kind = GT_SYSTEM; result->error = EBUSY; return; }
    char *argv[GT_ARG_COUNT + 1], bytes[GT_ARG_BYTES], directory[GT_CWD_BYTES + 1];
    result->error = unpack(packed, cwd, argv, bytes, directory);
    if (result->error) return;
    active = 1;
    cancelled = 0;
    struct signal_scope scope = {0};
    result->error = begin_signals(&scope);
    if (result->error) result->kind = GT_SYSTEM;
    else {
        int64_t start = now_ms();
        pid_t pid = 0;
        if (start < 0) { result->kind = GT_SYSTEM; result->error = errno; }
        else {
            int spawned = spawn_stage(&pid, argv, directory, start + deadline);
            result->error = spawned > 0 ? spawned : 0;
            result->kind = spawned > 0 ? GT_LAUNCH : GT_EXIT;
            if (spawned == GT_SPAWN_CANCEL) result->kind = GT_CANCEL;
            if (spawned == GT_SPAWN_DEADLINE) result->kind = GT_DEADLINE;
            result->pid = pid;
            sigset_t running = scope.old_mask;
            sigdelset(&running, SIGINT);
            sigdelset(&running, SIGTERM);
            sigaddset(&running, SIGCHLD);
            if (sigprocmask(SIG_SETMASK, &running, NULL) < 0) {
                result->kind = GT_SYSTEM; result->error = errno;
                if (pid > 0) { signal_group(pid, SIGKILL, result); reap(pid, result); }
            } else if (pid > 0) supervise(pid, start + deadline, grace, result);
            if (cancelled) { result->kind = GT_CANCEL; result->signal = cancelled; }
        }
    }
    int restore_error = end_signals(&scope);
    if (restore_error && !result->cleanup_error) result->cleanup_error = restore_error;
    if (result->cleanup_error && result->kind == GT_EXIT) result->kind = GT_SYSTEM;
    active = 0;
}
