/* R to CBOR, deterministically: design sections 7 and 8.
 *
 * Project code rather than TinyCBOR's encoder. RFC 8949 section 4.2.1 sorts
 * map entries by their encoded keys, so each key is encoded, the keys are
 * sorted, and their bytes are spliced into the output; TinyCBOR's encoder
 * counts every container's items and has no call that appends bytes it did
 * not produce (cbor_encoder_close_container() then fails TooFewItems).
 *
 * One pass writes into a growing malloc() buffer owned by a finalized
 * external pointer, so an error raised from anywhere frees it (design
 * section 12); the result is one copy into a RAWSXP of exactly the right
 * size, after which the buffer is freed eagerly. Stage 8 measured the
 * original two-pass design (measure, then write into an exact RAWSXP) at
 * twice the encoding time for no benefit a caller can see. */

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "zucbor.h"

typedef struct {
    const uint8_t *key;
    size_t key_len;
    R_xlen_t index;
} zu_entry;

typedef struct {
    uint8_t *out;           /* NULL while only counting (map keys) */
    size_t pos, cap;
    SEXP owner;             /* external pointer owning out; R_NilValue for scratch */
    int max_depth;
    int auto_unbox;
    SEXP call;
    zu_entry **pool;        /* map entry arrays, one per depth, reused */
    R_xlen_t *pool_cap;
    int *pool_top;          /* deepest pool entry set; shared, like pool */
    SEXP ns;                /* the namespace, where as_cbor() is called from */
} zu_encoder;

static void encode(zu_encoder *e, SEXP x, int depth);
static void encode_element(zu_encoder *e, SEXP x, R_xlen_t i, int depth);
static void check_depth(zu_encoder *e, int depth);

/* ---- faults ---------------------------------------------------------------- */

static void fail_encode(zu_encoder *e, const char *status, const char *detail)
{
    zu_fault f;
    f.status = status;
    f.detail = detail;
    f.offset = NA_REAL;
    f.limit = NULL;
    f.limit_value = NA_REAL;
    if (strcmp(status, ZU_ERR_DEPTH_LIMIT) == 0) {
        f.limit = "max_depth";
        f.limit_value = e->max_depth;
    }
    SEXP fault = PROTECT(zu_fault_sexp(&f));
    SEXP name = PROTECT(Rf_mkString("zucbor"));
    SEXP ns = PROTECT(R_FindNamespace(name));
    SEXP quoted = PROTECT(Rf_lang2(Rf_install("quote"), e->call));
    SEXP expr = PROTECT(Rf_lang3(Rf_install("zu_raise_fault"), fault, quoted));
    Rf_eval(expr, ns);
    UNPROTECT(5);
    Rf_error("zucbor: zu_raise_fault() returned");
}

/* ---- output ------------------------------------------------------------------ */

static void grow_output(zu_encoder *e, size_t need);
static void free_output(SEXP owner);

static void put(zu_encoder *e, const void *p, size_t n)
{
    if (e->owner != R_NilValue && e->pos + n > e->cap)
        grow_output(e, e->pos + n);
    if (e->out && n)
        memcpy(e->out + e->pos, p, n);
    e->pos += n;
}

static void put_byte(zu_encoder *e, uint8_t b)
{
    put(e, &b, 1);
}

/* A head in its shortest form (RFC 8949 section 4.2.1, rule 1). */
static void put_head(zu_encoder *e, int major, uint64_t v)
{
    uint8_t buf[9];
    uint8_t mt = (uint8_t)(major << 5);
    size_t n;
    if (v < 24) {
        buf[0] = (uint8_t)(mt | v);
        n = 1;
    } else if (v <= 0xff) {
        buf[0] = mt | 24;
        buf[1] = (uint8_t) v;
        n = 2;
    } else if (v <= 0xffff) {
        buf[0] = mt | 25;
        buf[1] = (uint8_t)(v >> 8);
        buf[2] = (uint8_t) v;
        n = 3;
    } else if (v <= 0xffffffffu) {
        buf[0] = mt | 26;
        for (int i = 0; i < 4; i++)
            buf[1 + i] = (uint8_t)(v >> (24 - 8 * i));
        n = 5;
    } else {
        buf[0] = mt | 27;
        for (int i = 0; i < 8; i++)
            buf[1 + i] = (uint8_t)(v >> (56 - 8 * i));
        n = 9;
    }
    put(e, buf, n);
}

/* ---- scalars ------------------------------------------------------------------- */

/* The shortest float that holds d exactly (design section 8, rule 3). */
static void put_float(zu_encoder *e, double d)
{
    if (isnan(d)) {
        const uint8_t nan[] = {0xf9, 0x7e, 0x00};
        put(e, nan, 3);
        return;
    }
    uint16_t h;
    if (zu_double_to_half(d, &h)) {
        uint8_t buf[3] = {0xf9, (uint8_t)(h >> 8), (uint8_t) h};
        put(e, buf, 3);
        return;
    }
    float f = (float) d;
    if ((double) f == d) {
        uint32_t u;
        memcpy(&u, &f, 4);
        uint8_t buf[5] = {0xfa, (uint8_t)(u >> 24), (uint8_t)(u >> 16), (uint8_t)(u >> 8), (uint8_t) u};
        put(e, buf, 5);
        return;
    }
    uint64_t u;
    memcpy(&u, &d, 8);
    uint8_t buf[9];
    buf[0] = 0xfb;
    for (int i = 0; i < 8; i++)
        buf[1 + i] = (uint8_t)(u >> (56 - 8 * i));
    put(e, buf, 9);
}

/* A double: an integer when it is whole, in CBOR's integer range and not
 * -0 (design section 7.1), else the shortest exact float. */
static void put_double(zu_encoder *e, double d)
{
    const double two64 = 18446744073709551616.0;
    if (R_FINITE(d) && d == trunc(d) && d >= -two64 && d < two64 && !(d == 0 && signbit(d))) {
        if (d >= 0) {
            put_head(e, 0, (uint64_t) d);
        } else {
            /* d = -1 - n, so n = -d - 1; -d is at most 2^64. */
            double m = -d;
            put_head(e, 1, m == two64 ? UINT64_MAX : (uint64_t) m - 1);
        }
        return;
    }
    put_float(e, d);
}

static void put_text(zu_encoder *e, SEXP s)
{
    if (Rf_getCharCE(s) == CE_BYTES)
        fail_encode(e, ZU_ERR_INVALID_VALUE, "a string marked as \"bytes\" has no text encoding");
    const void *vmax = vmaxget();
    const char *u = Rf_translateCharUTF8(s);
    size_t n = strlen(u);
    if (!zu_utf8_valid((const uint8_t *) u, n))
        fail_encode(e, ZU_ERR_INVALID_VALUE, "a string is not valid UTF-8");
    put_head(e, 3, n);
    put(e, u, n);
    vmaxset(vmax);
}

/* ---- classes ------------------------------------------------------------------- */

/* Tag 1: an instant, as whole seconds or the shortest exact float. A tag is
 * a level of depth, as the decoder counts it; depth is the tag's level. */
static void put_posixct(zu_encoder *e, double secs, int depth)
{
    if (ISNAN(secs)) {
        put_byte(e, 0xf6);
        return;
    }
    check_depth(e, depth);
    put_head(e, 6, 1);
    put_double(e, secs);
}

/* Tag 1004, "YYYY-MM-DD"; tag 100 (days) when the year has no four-digit
 * RFC 3339 form. Fractional days are dropped, as format.Date() does. */
static void put_date(zu_encoder *e, double days, int depth)
{
    if (!R_FINITE(days)) {
        put_byte(e, 0xf6);
        return;
    }
    check_depth(e, depth);
    days = floor(days);
    char buf[16];
    if (zu_format_full_date(days, buf) == 0) {
        put_head(e, 6, 1004);
        put_head(e, 3, 10);
        put(e, buf, 10);
    } else {
        put_head(e, 6, 100);
        put_double(e, days);
    }
}

static void put_bigint(zu_encoder *e, SEXP s, int depth)
{
    if (s == NA_STRING) {
        put_byte(e, 0xf6);
        return;
    }
    const char *p = CHAR(s);
    int negative = *p == '-';
    size_t n;
    const uint8_t *mag = zu_dec_to_magnitude(p + negative, &n);
    if (!mag)
        fail_encode(e, ZU_ERR_INVALID_VALUE, "a cbor_bigint is not a canonical decimal integer");
    /* For a negative value v, CBOR carries n = -1 - v, i.e. |v| - 1. */
    uint8_t *m = (uint8_t *) R_alloc(n + 1, 1);
    if (n)
        memcpy(m, mag, n);
    if (negative) {
        if (n == 0)
            fail_encode(e, ZU_ERR_INVALID_VALUE, "a cbor_bigint is \"-0\"");
        for (size_t i = n; i-- > 0;)
            if (m[i]-- != 0)
                break;
    }
    size_t start = 0;
    while (start < n && m[start] == 0)
        start++;
    size_t len = n - start;
    if (len <= 8) {
        uint64_t v = 0;
        for (size_t i = start; i < n; i++)
            v = (v << 8) | m[i];
        put_head(e, negative ? 1 : 0, v);
    } else {
        check_depth(e, depth);
        put_head(e, 6, negative ? 3 : 2);
        put_head(e, 2, len);
        put(e, m + start, len);
    }
}

/* Rf_inherits(), not OBJECT(): the latter is non-API in current R. */
static int is_class(SEXP x, const char *cls)
{
    return Rf_inherits(x, cls);
}

/* ---- maps --------------------------------------------------------------------- */

static int entry_cmp(const zu_entry *a, const zu_entry *b)
{
    size_t n = a->key_len < b->key_len ? a->key_len : b->key_len;
    int r = n ? memcmp(a->key, b->key, n) : 0;
    if (r)
        return r;
    return a->key_len < b->key_len ? -1 : (a->key_len > b->key_len ? 1 : 0);
}

/* Text keys by UTF-8 length, then bytes: the bytewise order of their
 * encodings, since a text head grows with the length (0x60 + n below 24,
 * then 0x78 n, 0x79 nn ...), so no key needs encoding to be sorted. */
static int text_cmp(const zu_entry *a, const zu_entry *b)
{
    if (a->key_len != b->key_len)
        return a->key_len < b->key_len ? -1 : 1;
    return a->key_len ? memcmp(a->key, b->key, a->key_len) : 0;
}

/* Merge sort: deterministic, and O(n log n) on any key order. Input that is
 * already in order, as most R lists are not but many maps built for a
 * protocol are, is detected in one pass and left alone. */
static void sort_entries(zu_entry *a, R_xlen_t n, int (*cmp)(const zu_entry *, const zu_entry *))
{
    R_xlen_t run = 1;
    while (run < n && cmp(&a[run - 1], &a[run]) < 0)
        run++;
    if (run >= n)
        return;
    zu_entry *tmp = (zu_entry *) R_alloc((size_t) n, sizeof(zu_entry));
    zu_entry *src = a, *dst = tmp;
    for (R_xlen_t width = 1; width < n; width *= 2) {
        for (R_xlen_t lo = 0; lo < n; lo += 2 * width) {
            R_xlen_t mid = lo + width < n ? lo + width : n;
            R_xlen_t hi = lo + 2 * width < n ? lo + 2 * width : n;
            R_xlen_t i = lo, j = mid, k = lo;
            while (i < mid && j < hi)
                dst[k++] = cmp(&src[j], &src[i]) < 0 ? src[j++] : src[i++];
            while (i < mid)
                dst[k++] = src[i++];
            while (j < hi)
                dst[k++] = src[j++];
        }
        zu_entry *t = src;
        src = dst;
        dst = t;
    }
    if (src != a)
        memcpy(a, src, (size_t) n * sizeof(zu_entry));
}

/* Encodes one key on its own and returns its bytes, in R_alloc() memory.
 * One pass, into a buffer of its own owned like the output: a key may hold
 * a class with an as_cbor() method, which must run once, not once per
 * pass. */
static const uint8_t *encode_key(zu_encoder *e, SEXP key, int depth, size_t *len)
{
    zu_encoder sub = *e;
    sub.out = NULL;
    sub.pos = sub.cap = 0;
    sub.owner = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(sub.owner, free_output, TRUE);
    encode(&sub, key, depth);
    uint8_t *buf = (uint8_t *) R_alloc(sub.pos ? sub.pos : 1, 1);
    if (sub.pos)
        memcpy(buf, sub.out, sub.pos);
    free_output(sub.owner);
    UNPROTECT(1);
    *len = sub.pos;
    return buf;
}

/* A map from keys (a list, or NULL with text names) and values, in RFC 8949
 * deterministic order. depth is the map's own level. */
static void put_map(zu_encoder *e, SEXP keys, SEXP names, SEXP values, R_xlen_t n, int depth)
{
    /* One entry array per depth, grown when needed: a nested map is at a
     * deeper level, so it never overwrites the array its parent is using. */
    if (!e->pool[depth] || e->pool_cap[depth] < n + 1) {
        e->pool_cap[depth] = n + 1 > 2 * e->pool_cap[depth] ? n + 1 : 2 * e->pool_cap[depth];
        e->pool[depth] = (zu_entry *) R_alloc((size_t) e->pool_cap[depth], sizeof(zu_entry));
        if (depth > *e->pool_top)
            *e->pool_top = depth;
    }
    zu_entry *entries = e->pool[depth];
    int text = keys == R_NilValue;
    /* Held until the map is written: translated names live in R_alloc(). */
    const void *vmax = vmaxget();
    for (R_xlen_t i = 0; i < n; i++) {
        if (text) {
            SEXP s = STRING_ELT(names, i);
            if (Rf_getCharCE(s) == CE_BYTES)
                fail_encode(e, ZU_ERR_INVALID_VALUE, "a string marked as \"bytes\" has no text encoding");
            const char *u = Rf_translateCharUTF8(s);
            entries[i].key = (const uint8_t *) u;
            entries[i].key_len = strlen(u);
            if (!zu_utf8_valid(entries[i].key, entries[i].key_len))
                fail_encode(e, ZU_ERR_INVALID_VALUE, "a name is not valid UTF-8");
        } else {
            entries[i].key = encode_key(e, VECTOR_ELT(keys, i), depth, &entries[i].key_len);
        }
        entries[i].index = i;
    }
    int (*cmp)(const zu_entry *, const zu_entry *) = text ? text_cmp : entry_cmp;
    sort_entries(entries, n, cmp);
    for (R_xlen_t i = 1; i < n; i++)
        if (cmp(&entries[i - 1], &entries[i]) == 0)
            fail_encode(e, ZU_ERR_DUPLICATE_KEY, "two map keys encode identically");
    put_head(e, 5, (uint64_t) n);
    for (R_xlen_t i = 0; i < n; i++) {
        if (text)
            put_head(e, 3, entries[i].key_len);
        put(e, entries[i].key, entries[i].key_len);
        if (TYPEOF(values) == VECSXP)
            encode(e, VECTOR_ELT(values, entries[i].index), depth);
        else
            encode_element(e, values, entries[i].index, depth);
    }
    vmaxset(vmax);
    /* That released the pools of the maps nested in this one: they were
     * allocated after vmax. Forget them, or the next map at their depth
     * would write into released memory. */
    for (int k = depth + 1; k <= *e->pool_top; k++) {
        e->pool[k] = NULL;
        e->pool_cap[k] = 0;
    }
    if (*e->pool_top > depth)
        *e->pool_top = depth;
}

/* Names that can be map keys: present on every element, not NA, not "". */
static int check_names(zu_encoder *e, SEXP names, R_xlen_t n)
{
    if (names == R_NilValue)
        return 0;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(names, i);
        if (s == NA_STRING || CHAR(s)[0] == '\0')
            fail_encode(e, ZU_ERR_INVALID_VALUE,
                        "names must be all present and non-empty, or absent");
    }
    return 1;
}

/* ---- vectors ------------------------------------------------------------------- */

/* One element of an atomic vector, or of a classed one. depth is the level a
 * tag would take, for the classes that write one. */
static void encode_element(zu_encoder *e, SEXP x, R_xlen_t i, int depth)
{
    switch (TYPEOF(x)) {
    case LGLSXP: {
        int v = LOGICAL(x)[i];
        put_byte(e, v == NA_LOGICAL ? 0xf6 : v ? 0xf5 : 0xf4);
        return;
    }
    case INTSXP: {
        int v = INTEGER(x)[i];
        if (is_class(x, "POSIXct")) {
            put_posixct(e, v == NA_INTEGER ? NA_REAL : (double) v, depth);
        } else if (is_class(x, "Date")) {
            put_date(e, v == NA_INTEGER ? NA_REAL : (double) v, depth);
        } else if (v == NA_INTEGER) {
            put_byte(e, 0xf6);
        } else if (is_class(x, "factor")) {
            SEXP levels = Rf_getAttrib(x, R_LevelsSymbol);
            if (TYPEOF(levels) != STRSXP || v < 1 || v > LENGTH(levels))
                fail_encode(e, ZU_ERR_INVALID_VALUE, "a factor code has no level");
            put_text(e, STRING_ELT(levels, v - 1));
        } else if (is_class(x, "cbor_simple")) {
            if (v < 0 || (v > 19 && v < 32) || v > 255)
                fail_encode(e, ZU_ERR_INVALID_VALUE, "a cbor_simple is not 0-19 or 32-255");
            if (v < 24)
                put_byte(e, (uint8_t)(0xe0 | v));
            else {
                put_byte(e, 0xf8);
                put_byte(e, (uint8_t) v);
            }
        } else {
            put_head(e, v < 0 ? 1 : 0, v < 0 ? (uint64_t)(-1 - (int64_t) v) : (uint64_t) v);
        }
        return;
    }
    case REALSXP: {
        double v = REAL(x)[i];
        if (is_class(x, "POSIXct"))
            put_posixct(e, v, depth);
        else if (is_class(x, "Date"))
            put_date(e, v, depth);
        else if (ISNA(v))
            put_byte(e, 0xf6);      /* NA_real_; NaN is a float */
        else
            put_double(e, v);
        return;
    }
    case STRSXP: {
        SEXP s = STRING_ELT(x, i);
        if (is_class(x, "cbor_bigint"))
            put_bigint(e, s, depth);
        else if (s == NA_STRING)
            put_byte(e, 0xf6);
        else
            put_text(e, s);
        return;
    }
    default:
        fail_encode(e, ZU_ERR_UNSUPPORTED_TYPE, "a vector of this type has no CBOR form");
    }
}

static int unboxed(const zu_encoder *e, SEXP x)
{
    return e->auto_unbox && XLENGTH(x) == 1 && !is_class(x, "AsIs");
}

static void check_depth(zu_encoder *e, int depth)
{
    if (depth > e->max_depth)
        fail_encode(e, ZU_ERR_DEPTH_LIMIT, NULL);
}

/* ---- as_cbor() ------------------------------------------------------------------ */

/* Classes cbor_encode() writes itself, or refuses itself. "AsIs" only marks
 * a value as not to be unboxed, so it neither counts as known nor asks for
 * a conversion. */
static const char *const known_classes[] = {
    "POSIXct", "Date", "factor", "cbor_simple", "cbor_bigint", "cbor_tag",
    "cbor_map", "data.frame", "POSIXlt", NULL
};

static int wants_conversion(SEXP x)
{
    if (!Rf_isObject(x))
        return 0;
    SEXP klass = Rf_getAttrib(x, R_ClassSymbol);
    if (TYPEOF(klass) != STRSXP)
        return 0;
    int unknown = 0;
    for (R_xlen_t i = 0; i < XLENGTH(klass); i++) {
        const char *c = CHAR(STRING_ELT(klass, i));
        for (const char *const *k = known_classes; *k; k++)
            if (strcmp(c, *k) == 0)
                return 0;
        if (strcmp(c, "AsIs") != 0)
            unknown = 1;
    }
    return unknown;
}

/* as_cbor(x), evaluated in a fresh environment whose parent is the
 * namespace: S3 dispatch finds methods registered by any package and those
 * in the global environment, and x is bound by name, so a method's error
 * shows `x`, not the deparsed value. */
static SEXP convert(zu_encoder *e, SEXP x)
{
    SEXP env = PROTECT(R_NewEnv(e->ns, FALSE, 1));
    SEXP sym = Rf_install("x");
    Rf_defineVar(sym, x, env);
    SEXP expr = PROTECT(Rf_lang2(Rf_install("as_cbor"), sym));
    SEXP out = Rf_eval(expr, env);
    UNPROTECT(2);
    return out;
}

static void encode_value(zu_encoder *e, SEXP x, int depth, int may_convert);

static void encode(zu_encoder *e, SEXP x, int depth)
{
    encode_value(e, x, depth, 1);
}

/* depth is the level of the container x would be; a scalar is no level.
 * An object of a class this encoder does not know goes through as_cbor()
 * once (design section 7.5): the method's result is not converted again,
 * though its elements are, so no chain of methods can loop. */
static void encode_value(zu_encoder *e, SEXP x, int depth, int may_convert)
{
    if (may_convert && wants_conversion(x)) {
        SEXP y = PROTECT(convert(e, x));
        if (y != x) {
            SEXP kx = PROTECT(Rf_getAttrib(x, R_ClassSymbol));
            SEXP ky = PROTECT(Rf_getAttrib(y, R_ClassSymbol));
            if (R_compute_identical(kx, ky, 16))
                fail_encode(e, ZU_ERR_UNSUPPORTED_TYPE,
                            "as_cbor() returned an object of the class it was given");
            UNPROTECT(2);
            encode_value(e, y, depth, 0);
            UNPROTECT(1);
            return;
        }
        UNPROTECT(1);
    }
    switch (TYPEOF(x)) {
    case NILSXP:
        put_byte(e, 0xf6);
        return;
    case RAWSXP:
        put_head(e, 2, (uint64_t) XLENGTH(x));
        put(e, RAW(x), (size_t) XLENGTH(x));
        return;
    case LGLSXP:
    case INTSXP:
    case REALSXP:
    case STRSXP: {
        if (is_class(x, "POSIXlt"))
            fail_encode(e, ZU_ERR_UNSUPPORTED_TYPE, "POSIXlt has no CBOR form; use as.POSIXct()");
        R_xlen_t n = XLENGTH(x);
        /* PROTECTed although reachable through x: rchk cannot see that. */
        SEXP names = PROTECT(Rf_getAttrib(x, R_NamesSymbol));
        if (check_names(e, names, n)) {
            check_depth(e, depth);
            put_map(e, R_NilValue, names, x, n, depth + 1);
            UNPROTECT(1);
            return;
        }
        UNPROTECT(1);
        if (unboxed(e, x)) {
            encode_element(e, x, 0, depth);
            return;
        }
        check_depth(e, depth);
        put_head(e, 4, (uint64_t) n);
        for (R_xlen_t i = 0; i < n; i++)
            encode_element(e, x, i, depth + 1);
        return;
    }
    case VECSXP: {
        if (is_class(x, "cbor_tag")) {
            check_depth(e, depth);
            SEXP t = VECTOR_ELT(x, 0);
            double tag = (TYPEOF(t) == REALSXP || TYPEOF(t) == INTSXP) && XLENGTH(t) == 1
                         ? Rf_asReal(t) : NA_REAL;
            if (!(tag >= 0 && tag <= 9007199254740992.0 && tag == trunc(tag)))
                fail_encode(e, ZU_ERR_INVALID_VALUE, "a cbor_tag number is not a whole number from 0 to 2^53");
            put_head(e, 6, (uint64_t) tag);
            encode(e, VECTOR_ELT(x, 1), depth + 1);
            return;
        }
        if (is_class(x, "cbor_map")) {
            SEXP keys = VECTOR_ELT(x, 0), values = VECTOR_ELT(x, 1);
            if (TYPEOF(keys) != VECSXP || TYPEOF(values) != VECSXP || XLENGTH(keys) != XLENGTH(values))
                fail_encode(e, ZU_ERR_INVALID_VALUE, "a cbor_map needs keys and values lists of equal length");
            check_depth(e, depth);
            put_map(e, keys, R_NilValue, values, XLENGTH(keys), depth + 1);
            return;
        }
        if (is_class(x, "data.frame"))
            fail_encode(e, ZU_ERR_UNSUPPORTED_TYPE, "data frames are not encoded in this version; convert to a list");
        if (is_class(x, "POSIXlt"))
            fail_encode(e, ZU_ERR_UNSUPPORTED_TYPE, "POSIXlt has no CBOR form; use as.POSIXct()");
        R_xlen_t n = XLENGTH(x);
        SEXP names = PROTECT(Rf_getAttrib(x, R_NamesSymbol));
        check_depth(e, depth);
        if (check_names(e, names, n)) {
            put_map(e, R_NilValue, names, x, n, depth + 1);
            UNPROTECT(1);
            return;
        }
        UNPROTECT(1);
        put_head(e, 4, (uint64_t) n);
        for (R_xlen_t i = 0; i < n; i++)
            encode(e, VECTOR_ELT(x, i), depth + 1);
        return;
    }
    default:
        fail_encode(e, ZU_ERR_UNSUPPORTED_TYPE,
                    TYPEOF(x) == CPLXSXP ? "complex numbers have no CBOR form"
                    : TYPEOF(x) == CLOSXP || TYPEOF(x) == BUILTINSXP || TYPEOF(x) == SPECIALSXP
                        ? "functions have no CBOR form"
                    : TYPEOF(x) == ENVSXP ? "environments have no CBOR form"
                    : TYPEOF(x) == S4SXP ? "S4 objects have no CBOR form"
                    : "this R type has no CBOR form");
    }
}

/* ---- entry point ------------------------------------------------------------------ */

static void free_output(SEXP owner)
{
    void *p = R_ExternalPtrAddr(owner);
    if (p) {
        R_ClearExternalPtr(owner);      /* clear first: eager free and GC are then safe */
        free(p);
    }
}

static void grow_output(zu_encoder *e, size_t need)
{
    size_t cap = e->cap ? e->cap : 256;
    while (cap < need) {
        if (cap > SIZE_MAX / 2)
            fail_encode(e, ZU_ERR_INVALID_VALUE, "the encoding is too large");
        cap *= 2;
    }
    uint8_t *p = realloc(e->out, cap);
    if (!p)
        fail_encode(e, ZU_ERR_INVALID_VALUE, "not enough memory for the encoding");
    e->out = p;
    e->cap = cap;
    R_SetExternalPtrAddr(e->owner, p);
}

SEXP zucbor_encode(SEXP x, SEXP opts, SEXP call, SEXP ns)
{
    if (TYPEOF(opts) != INTSXP || XLENGTH(opts) != 4)
        Rf_error("zucbor_encode: arguments must be validated in R");
    const int *o = INTEGER(opts);
    int sequence = o[0];
    zu_encoder e;
    memset(&e, 0, sizeof e);
    e.auto_unbox = o[1];
    int self_describe = o[2];
    e.max_depth = o[3];
    e.call = call;
    e.ns = ns;
    if (TYPEOF(ns) != ENVSXP)
        Rf_error("zucbor_encode: arguments must be validated in R");
    if (e.max_depth < 1 || e.max_depth > ZU_MAX_DEPTH_CAP)
        Rf_error("zucbor_encode: limits must be validated in R");
    /* depth runs to max_depth + 1: a map's entries sit one level below it */
    e.pool = (zu_entry **) R_alloc((size_t) e.max_depth + 2, sizeof(zu_entry *));
    e.pool_cap = (R_xlen_t *) R_alloc((size_t) e.max_depth + 2, sizeof(R_xlen_t));
    memset(e.pool, 0, ((size_t) e.max_depth + 2) * sizeof(zu_entry *));
    memset(e.pool_cap, 0, ((size_t) e.max_depth + 2) * sizeof(R_xlen_t));
    int pool_top = 0;
    e.pool_top = &pool_top;

    e.owner = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(e.owner, free_output, TRUE);

    R_xlen_t items = sequence ? XLENGTH(x) : 1;
    const uint8_t describe[] = {0xd9, 0xd9, 0xf7};
    for (R_xlen_t i = 0; i < items; i++) {
        if (self_describe)
            put(&e, describe, 3);
        encode(&e, sequence ? VECTOR_ELT(x, i) : x, 1);
    }
    if (e.pos > (size_t) R_XLEN_T_MAX)
        fail_encode(&e, ZU_ERR_INVALID_VALUE, "the encoding is longer than an R vector can be");
    SEXP out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) e.pos));
    if (e.pos)
        memcpy(RAW(out), e.out, e.pos);
    free_output(e.owner);
    UNPROTECT(2);
    return out;
}

/* Test hook, design section 16: every binary16 pattern, decoded to a double
 * and encoded again, must come back as the same three bytes, NaNs as the
 * canonical 0x7e00. Returns the number of patterns that do not. */
SEXP zucbor_half_roundtrip(void)
{
    int bad = 0;
    for (uint32_t h = 0; h < 65536u; h++) {
        double d = zu_half_to_double((uint16_t) h);
        uint8_t buf[9];
        zu_encoder e;
        memset(&e, 0, sizeof e);
        e.out = buf;
        e.owner = R_NilValue;
        put_float(&e, d);
        uint16_t want = isnan(d) ? 0x7e00 : (uint16_t) h;
        if (e.pos != 3 || buf[0] != 0xf9 || buf[1] != (uint8_t)(want >> 8) || buf[2] != (uint8_t) want)
            bad++;
    }
    return Rf_ScalarInteger(bad);
}
