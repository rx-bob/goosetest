// Purpose-built process oracle; never linked into the production adapter.
#define _DARWIN_C_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void exit_cleanly(int signal) { (void)signal; _exit(0); }

int main(int argc, char **argv) {
    if (argc < 2) return 90;
    if (!strcmp(argv[1], "ok")) return 0;
    if (!strcmp(argv[1], "home")) {
        const char *home = getenv("GOOSE_HOME");
        return argc == 3 && home && !strcmp(home, argv[2]) ? 0 : 98;
    }
    if (!strcmp(argv[1], "stdin")) {
        char line[128];
        if (!fgets(line, sizeof line, stdin)) return 97;
        printf("stdin=%s", line);
        return 0;
    }
    if (!strcmp(argv[1], "echo")) {
        char cwd[4096];
        if (!getcwd(cwd, sizeof cwd)) return 91;
        printf("cwd=%s\n", cwd);
        for (int i = 2; i < argc; ++i) printf("arg=%s\n", argv[i]);
        fprintf(stderr, "child stderr inherited\n");
        return 0;
    }
    if (!strcmp(argv[1], "exit")) return argc == 3 ? atoi(argv[2]) : 92;
    if (!strcmp(argv[1], "signal")) { raise(SIGUSR1); return 93; }
    if (argc != 3) return 94;
    if (!strcmp(argv[1], "graceful")) {
        signal(SIGINT, exit_cleanly);
        signal(SIGTERM, exit_cleanly);
    } else {
        signal(SIGINT, SIG_IGN);
        signal(SIGTERM, SIG_IGN);
    }
    pid_t descendant = 0;
    if (!strcmp(argv[1], "tree") || !strcmp(argv[1], "orphan")) {
        descendant = fork();
        if (descendant < 0) return 95;
        if (!descendant) { for (;;) pause(); }
        // The leader exits on TERM; its descendant still requires escalation.
        signal(SIGTERM, SIG_DFL);
    }
    FILE *ready = fopen(argv[2], "w");
    if (!ready) return 96;
    fprintf(ready, "%ld %ld\n", (long)getpid(), (long)descendant);
    fclose(ready);
    if (!strcmp(argv[1], "orphan")) return 0;
    for (;;) pause();
}
