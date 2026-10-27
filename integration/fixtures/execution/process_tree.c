// Finite hostile child tree for independently observed CLI cancellation/deadline checks.
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void gt_pipeline_wait(void) {
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGALRM, SIG_DFL);
    alarm(30);
    pid_t child = fork();
    if (child < 0) _exit(90);
    if (child == 0) {
        alarm(30);
        for (;;) pause();
    }
    FILE *ready = fopen("owned-pids", "w");
    if (!ready) {
        kill(child, SIGKILL);
        _exit(91);
    }
    fprintf(ready, "%ld %ld\n", (long)getpid(), (long)child);
    if (fclose(ready) != 0) {
        kill(child, SIGKILL);
        _exit(92);
    }
    for (;;) pause();
}
