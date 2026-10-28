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
    int ready_pipe[2];
    if (pipe(ready_pipe) < 0) _exit(90);
    pid_t child = fork();
    if (child < 0) _exit(91);
    if (child == 0) {
        close(ready_pipe[0]);
        alarm(30);
        char ready_byte = '1';
        if (write(ready_pipe[1], &ready_byte, 1) != 1) _exit(92);
        close(ready_pipe[1]);
        for (;;) pause();
    }
    close(ready_pipe[1]);
    char ready_byte;
    if (read(ready_pipe[0], &ready_byte, 1) != 1 || ready_byte != '1') {
        kill(child, SIGKILL);
        _exit(93);
    }
    close(ready_pipe[0]);
    FILE *ready_file = fopen("owned-pids", "w");
    if (!ready_file) {
        kill(child, SIGKILL);
        _exit(94);
    }
    fprintf(ready_file, "%ld %ld\n", (long)getpid(), (long)child);
    if (fclose(ready_file) != 0) {
        kill(child, SIGKILL);
        _exit(95);
    }
    for (;;) pause();
}
