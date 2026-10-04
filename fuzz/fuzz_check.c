/* libFuzzer target: the check phase (src/zu_walk.c), R-free.
 *
 * The first byte chooses the options; the rest is the input. Besides
 * sanitizer findings, it traps on a broken invariant: relaxing an option
 * can only accept more, never less.
 *   deterministic = TRUE passes  =>  FALSE passes
 *   duplicate_keys = FALSE passes =>  TRUE passes
 *   a max_depth passes           =>  the ceiling passes
 *   an item passes               =>  so does the sequence of that one item
 *   an item passes               =>  as a prefix, consuming every byte
 *   a prefix passes, consuming n =>  the first n bytes pass as an item
 * and, for a stream (cbor_read_seq(each =), roadmap Stage 15):
 *   a sequence passes            =>  it streams to its end
 *   a stream stops at c          =>  the first c bytes pass as a sequence,
 *                                    and the rest streams no further
 *   an item passes               =>  every proper prefix of it is
 *                                    truncation, not a fault */
#include <stddef.h>
#include <stdint.h>

#include "zu_check.h"

void zu_arena_reset(void);

static int check(const uint8_t *data, size_t size, zu_check_opts opt, zu_plan *plan)
{
    zu_fault fault;
    return zu_check(data, size, &opt, plan, &fault) == 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 1)
        return 0;
    uint8_t o = data[0];
    zu_check_opts opt;
    opt.sequence = o & 1;
    opt.deterministic = (o >> 1) & 1;
    opt.duplicate_keys = (o >> 2) & 1;
    opt.max_depth = 1 + ((o >> 3) & 15) * 8;      /* 1 .. 121 */
    opt.max_items = (o & 0x80) ? 64 : UINT64_MAX;
    opt.prefix = 0;
    opt.stream = 0;
    data++;
    size--;

    zu_plan plan;
    int ok = check(data, size, opt, &plan);
    if (ok) {
        if (!opt.sequence && plan.n_items != 1)
            __builtin_trap();
        for (size_t i = 0; i < plan.n; i++)
            if (plan.counts[i] > size)
                __builtin_trap();
        zu_check_opts relaxed = opt;
        relaxed.deterministic = 0;
        relaxed.duplicate_keys = 1;
        relaxed.max_depth = ZU_MAX_DEPTH_CAP;
        relaxed.max_items = UINT64_MAX;
        relaxed.sequence = 1;
        if (!check(data, size, relaxed, NULL))
            __builtin_trap();
    }
    if (!opt.sequence) {
        zu_check_opts prefix = opt;
        zu_plan pp;
        prefix.prefix = 1;
        int pok = check(data, size, prefix, &pp);
        if (ok && (!pok || pp.consumed != size))
            __builtin_trap();
        if (pok && (pp.consumed == 0 || pp.consumed > size || pp.n_items != 1
                    || !check(data, pp.consumed, opt, NULL)))
            __builtin_trap();
    }

    zu_check_opts stream = opt;
    zu_plan sp;
    stream.sequence = 1;
    stream.stream = 1;
    int sok = check(data, size, stream, &sp);
    if (ok && opt.sequence && (!sok || sp.consumed != size))
        __builtin_trap();
    if (sok) {
        zu_check_opts seq = opt;
        zu_plan rest;
        seq.sequence = 1;
        seq.max_items = UINT64_MAX;     /* the stream's is per item */
        if (sp.consumed > size || !check(data, sp.consumed, seq, NULL))
            __builtin_trap();
        if (sp.consumed < size && check(data + sp.consumed, size - sp.consumed, stream, &rest)
            && rest.consumed != 0)
            __builtin_trap();
    }
    if (ok && !opt.sequence) {
        /* Every proper prefix when the item is short, three when not. */
        size_t cuts[3] = {1, size / 2, size - 1};
        size_t n = size <= 64 ? size - 1 : 3;
        for (size_t i = 0; i < n; i++) {
            size_t cut = size <= 64 ? i + 1 : cuts[i];
            zu_plan tp;
            if (cut == 0 || cut >= size)
                continue;
            if (!check(data, cut, stream, &tp) || tp.n_items != 0 || tp.consumed != 0)
                __builtin_trap();
        }
    }
    zu_arena_reset();
    return 0;
}
