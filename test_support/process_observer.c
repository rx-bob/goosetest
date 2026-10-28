// Observe wait ownership and restoration without trusting ProcessResult flags.
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static struct sigaction saved_int, saved_term;
static sigset_t saved_mask;
static char saved_home[4096];
static int saved_home_present;
static void ignored(int number) { (void)number; }

int32_t gt_test_process_reaped(int64_t pid) {
    int status;
    return waitpid((pid_t)pid, &status, WNOHANG) == -1 && errno == ECHILD;
}

int32_t gt_test_process_home_save(void) {
    const char *home = getenv("GOOSE_HOME");
    saved_home_present = home != NULL;
    if (!home) { saved_home[0] = 0; return 1; }
    size_t length = strnlen(home, sizeof saved_home);
    if (length >= sizeof saved_home) return 0;
    memcpy(saved_home, home, length + 1);
    return 1;
}

int32_t gt_test_process_home_unchanged(void) {
    const char *home = getenv("GOOSE_HOME");
    if ((home != NULL) != saved_home_present) return 0;
    return !home || !strcmp(home, saved_home);
}

int32_t gt_test_process_begin(void) {
    if (sigprocmask(SIG_SETMASK, NULL, &saved_mask)) return 0;
    struct sigaction action = {0};
    action.sa_handler = ignored;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGINT, &action, &saved_int) || sigaction(SIGTERM, &action, &saved_term)) return 0;
    sigset_t blocked = saved_mask;
    sigaddset(&blocked, SIGTERM);
    return sigprocmask(SIG_SETMASK, &blocked, NULL) == 0;
}

int32_t gt_test_process_end(void) {
    struct sigaction action_int, action_term;
    sigset_t mask;
    int ok = !sigaction(SIGINT, NULL, &action_int) && !sigaction(SIGTERM, NULL, &action_term)
        && !sigprocmask(SIG_SETMASK, NULL, &mask);
    ok = ok && action_int.sa_handler == ignored && action_term.sa_handler == ignored
        && sigismember(&mask, SIGTERM);
    for (int i = 1; i < NSIG; ++i) {
        if (i != SIGTERM && sigismember(&mask, i) != sigismember(&saved_mask, i)) ok = 0;
    }
    if (sigaction(SIGINT, &saved_int, NULL) || sigaction(SIGTERM, &saved_term, NULL)
        || sigprocmask(SIG_SETMASK, &saved_mask, NULL)) return 0;
    return ok;
}
