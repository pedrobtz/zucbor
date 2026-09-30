/* zu_scratch() for the R-free build (zu_check.h): an arena of malloc()ed
 * blocks, freed together by zu_arena_reset() after each input, as R frees
 * R_alloc() memory when a .Call returns. */
#include <stdlib.h>

#include "zu_check.h"

struct block {
    struct block *next;
    max_align_t data[];
};

static struct block *blocks;

void *zu_scratch(size_t n, size_t size)
{
    if (size && n > (SIZE_MAX - sizeof(struct block)) / size)
        abort();
    size_t bytes = n * size;
    struct block *b = malloc(sizeof(struct block) + (bytes > 0 ? bytes : 1));
    if (!b)
        abort();
    b->next = blocks;
    blocks = b;
    return b->data;
}

void zu_arena_reset(void)
{
    while (blocks) {
        struct block *next = blocks->next;
        free(blocks);
        blocks = next;
    }
}
