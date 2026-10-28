#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <signal.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
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

void goosetest_fixture_socket_wait(void) {
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    alarm(30);
    int ready[2];
    if (pipe(ready) < 0) _exit(95);
    pid_t child = fork();
    if (child < 0) _exit(96);
    if (child == 0) {
        close(ready[0]);
        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        int listener = socket(AF_INET, SOCK_STREAM, 0);
        if (listener < 0) { perror("fixture socket"); _exit(97); }
        struct sockaddr_in address = {0};
        address.sin_len = sizeof address;
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = 0;
        if (bind(listener, (struct sockaddr *)&address, sizeof address) < 0) {
            perror("fixture bind");
            _exit(98);
        }
        if (listen(listener, 1) < 0) { perror("fixture listen"); _exit(98); }
        socklen_t length = sizeof address;
        if (getsockname(listener, (struct sockaddr *)&address, &length) < 0) {
            perror("fixture getsockname");
            _exit(99);
        }
        FILE *port = fopen("owned-port", "w");
        if (!port) _exit(100);
        if (fprintf(port, "%u\n", (unsigned)ntohs(address.sin_port)) < 0 || fclose(port) != 0)
            _exit(101);
        char signal_byte = '1';
        if (write(ready[1], &signal_byte, 1) != 1) _exit(102);
        close(ready[1]);
        alarm(30);
        for (;;) pause();
    }
    close(ready[1]);
    char signal_byte;
    if (read(ready[0], &signal_byte, 1) != 1 || signal_byte != '1') _exit(103);
    close(ready[0]);
    FILE *pids = fopen("owned-pids", "w");
    if (!pids) _exit(104);
    if (fprintf(pids, "%ld %ld\n", (long)getpid(), (long)child) < 0 || fclose(pids) != 0)
        _exit(105);
    for (;;) pause();
}

int goosetest_fixture_rebind_socket(void) {
    FILE *port_file = fopen("owned-port", "r");
    if (!port_file) return 0;
    unsigned port;
    int read_error = fscanf(port_file, "%u", &port) != 1 || port == 0 || port > 65535;
    if (fclose(port_file) != 0 || read_error) return 0;
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) return 0;
    struct sockaddr_in address = {0};
    address.sin_len = sizeof address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((uint16_t)port);
    int rebound = bind(listener, (struct sockaddr *)&address, sizeof address) == 0
        && listen(listener, 1) == 0;
    close(listener);
    return rebound;
}

void goosetest_fixture_corrupt_completion(void) {
    const char *path = getenv("GOOSETEST_COMPLETION_PATH");
    if (!path) _exit(92);
    FILE *completion = fopen(path, "w");
    if (!completion) _exit(93);
    if (fputs("bad\n", completion) < 0 || fclose(completion) != 0) _exit(94);
}
