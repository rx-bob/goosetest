// Launch the process oracle with duplicate inherited GOOSE_HOME entries.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    char *arguments[] = {
        argv[1], "goose-home", argv[2], argv[3],
        "isolated compiler cache", "override cache", NULL
    };
    char *environment[] = {
        "PATH=/usr/bin:/bin", "GOOSE_HOME=old-one", "GOOSE_HOME=old-two", NULL
    };
    execve(argv[1], arguments, environment);
    perror("execve");
    return errno ? errno : 3;
}
