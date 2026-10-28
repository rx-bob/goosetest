#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <signal.h>
#include <sys/proc.h>
#include <sys/sysctl.h>
#include <unistd.h>

static int calls;

int goosetest_fixture_next(void) {
    ++calls;
    FILE *observations = fopen("process-observations", "a");
    if (!observations) return -1;
    int error = fprintf(observations, "%ld %d\n", (long)getpid(), calls) < 0;
    if (fclose(observations) != 0) error = 1;
    return error ? -1 : calls;
}

void goosetest_fixture_abort(void) {
    pid_t child = fork();
    if (child < 0) _exit(90);
    if (child == 0) {
        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        alarm(30);
        for (;;) pause();
    }
    FILE *descendant = fopen("crash-descendant", "w");
    if (!descendant) _exit(91);
    if (fprintf(descendant, "%ld\n", (long)child) < 0 || fclose(descendant) != 0) _exit(92);
    abort();
}

int goosetest_fixture_descendant_stopped(void) {
    FILE *descendant = fopen("crash-descendant", "r");
    if (!descendant) return -1;
    long pid;
    int read_error = fscanf(descendant, "%ld", &pid) != 1;
    if (fclose(descendant) != 0 || read_error || pid <= 0) return -1;
    struct kinfo_proc info = {0};
    size_t size = sizeof info;
    int query[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)pid};
    if (sysctl(query, 4, &info, &size, NULL, 0) < 0) return errno == ESRCH ? 1 : -1;
    return size == 0 || info.kp_proc.p_pid != pid || info.kp_proc.p_stat == SZOMB;
}

void goosetest_fixture_corrupt_completion(void) {
    const char *path = getenv("GOOSETEST_COMPLETION_PATH");
    if (!path) _exit(92);
    FILE *completion = fopen(path, "w");
    if (!completion) _exit(93);
    if (fputs("bad\n", completion) < 0 || fclose(completion) != 0) _exit(94);
}
