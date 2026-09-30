/* RFC 8949 section 8 diagnostic notation, through TinyCBOR's cborpretty.c.
 * It writes through a printf-style callback, never stdio; this callback
 * formats into R_alloc() scratch, so nothing leaks if R unwinds. The format
 * strings carry <inttypes.h> macros, which is why Makevars sets
 * __USE_MINGW_ANSI_STDIO (design section 13, trap 5). */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "zucbor.h"
#include "cbor.h"

typedef struct {
    char *buf;
    size_t len, cap;
} zu_text;

static void reserve(zu_text *t, size_t need)
{
    if (t->len + need + 1 <= t->cap)
        return;
    size_t cap = t->cap ? t->cap : 256;
    while (cap < t->len + need + 1)
        cap *= 2;
    char *buf = (char *) R_alloc(cap, 1);
    if (t->len)
        memcpy(buf, t->buf, t->len);
    t->buf = buf;
    t->cap = cap;
}

#ifdef __GNUC__
__attribute__((format(printf, 2, 3)))
#endif
static CborError append(void *token, const char *fmt, ...)
{
    zu_text *t = (zu_text *) token;
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (n < 0)
        return CborErrorIO;
    reserve(t, (size_t) n);
    va_start(ap, fmt);
    vsnprintf(t->buf + t->len, (size_t) n + 1, fmt, ap);
    va_end(ap);
    t->len += (size_t) n;
    return CborNoError;
}

/* The diagnostic notation of the item at *it, which is left where it was.
 * The text is R_alloc()ed and NUL-terminated; its length goes to *len. The
 * item must already have passed the check phase. */
const char *zu_diagnose_item(const CborValue *it, size_t *len)
{
    zu_text t = {NULL, 0, 0};
    CborValue copy = *it;
    reserve(&t, 0);
    CborError err = cbor_value_to_pretty_stream(append, &t, &copy, CborPrettyDefaultFlags);
    if (err)
        Rf_error("zucbor: diagnostic notation failed on checked input (%d)", (int) err);
    t.buf[t.len] = '\0';
    *len = t.len;
    return t.buf;
}
