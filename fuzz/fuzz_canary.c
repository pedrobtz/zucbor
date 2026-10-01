/* The fuzz gate's canary (roadmap Stage 7): links the same check phase and
 * traps as soon as it accepts an input, which the seed corpus guarantees.
 * tools/run-fuzz requires this to crash before trusting any real target: a
 * gate is trusted once it has been seen to fail. */
#include <stddef.h>
#include <stdint.h>

#include "zu_check.h"

void zu_arena_reset(void);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    zu_check_opts opt = {ZU_MAX_DEPTH_CAP, UINT64_MAX, 1, 0, 1, 0};
    zu_fault fault;
    int ok = zu_check(data, size, &opt, NULL, &fault) == 0 && size > 0;
    zu_arena_reset();
    if (ok)
        __builtin_trap();
    return 0;
}
