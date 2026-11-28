#include <signal.h>

/* SIG_IGN cannot be represented as a Zig function pointer on architectures
 * that require function-pointer alignment (e.g. aarch64). Keep this tiny C
 * helper so setup() can ignore SIGPIPE portably. */
void acwm_ignore_sigpipe(void) {
    signal(SIGPIPE, SIG_IGN);
}
