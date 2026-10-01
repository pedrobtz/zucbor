/* Prints the status the check phase gives one input, for
 * tools/run-mutation-check. Usage:
 *   probe HEX [sequence deterministic duplicate_keys max_depth max_items]
 * Prints "ok" or the fault's status name. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zu_check.h"

void zu_arena_reset(void);

int main(int argc, char **argv)
{
    if (argc < 2)
        return 2;
    size_t n = strlen(argv[1]) / 2;
    uint8_t *buf = malloc(n ? n : 1);
    for (size_t i = 0; i < n; i++) {
        unsigned v;
        sscanf(argv[1] + 2 * i, "%2x", &v);
        buf[i] = (uint8_t) v;
    }
    zu_check_opts opt = {256, UINT64_MAX, 0, 0, 0, 0};
    if (argc >= 7) {
        opt.sequence = atoi(argv[2]);
        opt.deterministic = atoi(argv[3]);
        opt.duplicate_keys = atoi(argv[4]);
        opt.max_depth = atoi(argv[5]);
        opt.max_items = strtoull(argv[6], NULL, 10);
    }
    zu_fault fault;
    puts(zu_check(buf, n, &opt, NULL, &fault) ? fault.status : "ok");
    zu_arena_reset();
    free(buf);
    return 0;
}
