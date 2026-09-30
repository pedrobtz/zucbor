/* Wide integers as exact decimal text (design section 6.2): the payload of
 * cbor_bigint. No printf: PRIu64 and friends mean different things to MSVC-
 * and C99-style runtimes, and none of this needs a format string. */
#include <string.h>

#include "zucbor.h"

/* Decimal digits of v into buf (at least 21 bytes), NUL-terminated.
 * Returns the length. */
size_t zu_u64_to_dec(uint64_t v, char *buf)
{
    char tmp[21];
    size_t n = 0;
    do {
        tmp[n++] = (char)('0' + (int)(v % 10));
        v /= 10;
    } while (v);
    for (size_t i = 0; i < n; i++)
        buf[i] = tmp[n - 1 - i];
    buf[n] = '\0';
    return n;
}

/* The decimal text of a big-endian magnitude, plus one when add_one, with a
 * leading '-' when negative. RFC 8949 tag 3 carries n for the value -1 - n,
 * hence add_one. Quadratic in the length, which the caller bounds
 * (ZU_BIGNUM_MAX_BYTES). The result is R_alloc()ed. */
const char *zu_magnitude_to_dec(const uint8_t *mag, size_t n, int add_one, int negative)
{
    /* Work on a copy one byte longer, so adding one can carry out. */
    uint8_t *work = (uint8_t *) R_alloc(n + 1, 1);
    work[0] = 0;
    if (n)
        memcpy(work + 1, mag, n);
    size_t len = n + 1;
    if (add_one) {
        for (size_t i = len; i-- > 0;) {
            if (++work[i] != 0)
                break;
        }
    }
    size_t start = 0;
    while (start < len && work[start] == 0)
        start++;

    /* Each pass divides by 10^9 and keeps the remainder: nine digits. */
    size_t max_chunks = len * 3 / 8 + 2;     /* 256^k < 10^(9 * (3k/8 + 1)) */
    uint32_t *chunks = (uint32_t *) R_alloc(max_chunks, sizeof(uint32_t));
    size_t n_chunks = 0;
    while (start < len) {
        uint64_t rem = 0;
        for (size_t i = start; i < len; i++) {
            uint64_t cur = rem * 256u + work[i];
            work[i] = (uint8_t)(cur / 1000000000u);
            rem = cur % 1000000000u;
        }
        chunks[n_chunks++] = (uint32_t) rem;
        while (start < len && work[start] == 0)
            start++;
    }

    char *out = (char *) R_alloc(n_chunks * 9 + 3, 1);
    size_t k = 0;
    if (negative)
        out[k++] = '-';
    if (n_chunks == 0) {
        out[k++] = '0';
    } else {
        char digits[21];
        size_t d = zu_u64_to_dec(chunks[n_chunks - 1], digits);
        memcpy(out + k, digits, d);
        k += d;
        for (size_t c = n_chunks - 1; c-- > 0;) {
            uint32_t v = chunks[c];
            for (int i = 8; i >= 0; i--) {
                out[k + (size_t)i] = (char)('0' + (int)(v % 10));
                v /= 10;
            }
            k += 9;
        }
    }
    out[k] = '\0';
    return out;
}
