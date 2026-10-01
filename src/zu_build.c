/* The build phase: CBOR to R, design section 6.
 *
 * It runs only after zu_check() has accepted the whole input, and trusts
 * nothing but what the check established: the input is well-formed and
 * valid, no deeper than max_depth, and plan->counts holds every container's
 * element count in preorder, which is the order this recursion meets them.
 * So no length header is read for allocation here, and the recursion depth
 * is bounded by max_depth (at most ZU_MAX_DEPTH_CAP).
 *
 * Every TinyCBOR accessor is still called only after the item's type has
 * been checked: under -DNDEBUG a violated precondition is unreachable(), not
 * an assert (design section 13, trap 3).
 *
 * Faults the check cannot see -- values R cannot hold, a tag 0 string that
 * is not RFC 3339 -- are raised from here through zu_raise_fault() in R, which
 * longjmps. That is safe because everything held is either PROTECTed or
 * R_alloc()ed (design section 12). */

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "zu_cbor.h"

#define ZU_INTERRUPT_EVERY 65536u

/* Bignum payloads longer than this stay cbor_tag: decimal conversion is
 * quadratic in the length (design section 6.6). */
#define ZU_BIGNUM_MAX_BYTES 128

enum { SIMPLIFY_PRESERVE, SIMPLIFY_NONE };
enum { KEYS_AUTO, KEYS_MAP, KEYS_STRING };
enum { TAGS_CONVERT, TAGS_KEEP };
enum { BIG_BIGINT, BIG_DOUBLE, BIG_ERROR };

/* What an element is, for the array lattice (design section 6.3). A float
 * and an integer-valued double are different kinds even though both are R
 * doubles: the lattice must not decide from a value's magnitude what type
 * its neighbours become. */
enum {
    K_NULL, K_LGL, K_INT, K_INTDBL, K_FLOAT, K_BIGINT, K_STR,
    K_POSIXCT, K_DATE, K_OTHER, K_COUNT
};

typedef struct {
    const uint8_t *buf;
    const zu_plan *plan;
    size_t next_count;
    int simplify, map_keys, tags, big_integers, duplicate_keys;
    SEXP call;
    uint64_t items;
    const double *handler_tags;     /* sorted; NULL when there are no handlers */
    R_xlen_t n_handlers;
    SEXP handlers;                  /* the functions, in handler_tags' order */
    SEXP ns;
} zu_builder;

static SEXP build(zu_builder *b, CborValue *it, int *kind);

/* ---- faults ---------------------------------------------------------------- */

static void fail_build(zu_builder *b, const char *status, const char *detail, const uint8_t *at)
{
    zu_fault f;
    f.status = status;
    f.detail = detail;
    f.offset = at ? (double)(at - b->buf) : NA_REAL;
    f.limit = NULL;
    f.limit_value = NA_REAL;
    SEXP fault = PROTECT(zu_fault_sexp(&f));
    SEXP name = PROTECT(Rf_mkString("zucbor"));
    SEXP ns = PROTECT(R_FindNamespace(name));
    /* The call is data: quote it so evaluating the expression cannot run it. */
    SEXP quoted = PROTECT(Rf_lang2(Rf_install("quote"), b->call));
    SEXP expr = PROTECT(Rf_lang3(Rf_install("zu_raise_fault"), fault, quoted));
    Rf_eval(expr, ns);
    UNPROTECT(5);
    Rf_error("zucbor: zu_raise_fault() returned");
}

/* TinyCBOR failing on input the check accepted is a bug in zucbor. */
static void internal(zu_builder *b, CborError err, const uint8_t *at)
{
    const char *name = zu_cbor_status_name(err);
    fail_build(b, name ? name : "CborUnknownError", cbor_error_string(err), at);
}

/* ---- scalars ------------------------------------------------------------------ */

/* The only place a CHARSXP is made from CBOR text, so values, names and keys
 * share the two guards (the zujson invariant, design section 6.8). */
static SEXP zu_mkchar(zu_builder *b, const char *s, size_t n, const uint8_t *at)
{
    if (n > INT_MAX)
        fail_build(b, ZU_ERR_STRING_TOO_LONG, "text string longer than an R string can be", at);
    if (n && memchr(s, 0, n))
        fail_build(b, ZU_ERR_NUL_IN_TEXT, "text string contains U+0000", at);
    return Rf_mkCharLenCE(s, (int) n, CE_UTF8);
}

static SEXP scalar_bigint(const char *dec)
{
    SEXP out = PROTECT(Rf_mkString(dec));
    Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("cbor_bigint"));
    UNPROTECT(1);
    return out;
}

/* An integer of value (negative ? -1 - raw : raw), design section 6.2. */
static SEXP integer_value(zu_builder *b, uint64_t raw, int negative, int *kind,
                          const uint8_t *at)
{
    if (!negative ? raw <= (uint64_t) INT_MAX : raw <= (uint64_t) INT_MAX - 1) {
        *kind = K_INT;
        return Rf_ScalarInteger(negative ? -1 - (int) raw : (int) raw);
    }
    const uint64_t two53 = UINT64_C(1) << 53;
    if (!negative ? raw <= two53 : raw <= two53 - 1) {
        *kind = K_INTDBL;
        return Rf_ScalarReal(negative ? -1.0 - (double) raw : (double) raw);
    }
    if (b->big_integers == BIG_ERROR)
        fail_build(b, ZU_ERR_BIG_INTEGER, "integer beyond 2^53 with big_integers = \"error\"", at);
    if (b->big_integers == BIG_DOUBLE) {
        *kind = K_INTDBL;
        if (!negative)
            return Rf_ScalarReal((double) raw);
        return Rf_ScalarReal(raw == UINT64_MAX ? -18446744073709551616.0
                                               : -(double)(raw + 1));
    }
    char dec[24];
    if (negative) {
        /* -1 - raw, printed as the magnitude raw + 1. */
        dec[0] = '-';
        if (raw == UINT64_MAX)
            memcpy(dec + 1, "18446744073709551616", 21);
        else
            zu_u64_to_dec(raw + 1, dec + 1);
    } else {
        zu_u64_to_dec(raw, dec);
    }
    *kind = K_BIGINT;
    return scalar_bigint(dec);
}

static SEXP classed_real(double v, const char *cls, int with_tz)
{
    SEXP out = PROTECT(Rf_ScalarReal(v));
    if (with_tz) {
        SEXP klass = PROTECT(Rf_allocVector(STRSXP, 2));
        SET_STRING_ELT(klass, 0, Rf_mkChar("POSIXct"));
        SET_STRING_ELT(klass, 1, Rf_mkChar("POSIXt"));
        Rf_setAttrib(out, R_ClassSymbol, klass);
        SEXP tz = PROTECT(Rf_mkString("UTC"));
        Rf_setAttrib(out, Rf_install("tzone"), tz);
        UNPROTECT(2);
    } else {
        Rf_setAttrib(out, R_ClassSymbol, Rf_mkString(cls));
    }
    UNPROTECT(1);
    return out;
}

/* The text or bytes of the string at *it, joined across chunks, advancing
 * *it past it. Text is R_alloc()ed; bytes go straight into a RAWSXP. */
static const char *read_text(zu_builder *b, CborValue *it, size_t *n)
{
    const uint8_t *at = cbor_value_get_next_byte(it);
    size_t len;
    CborError err;
    /* A definite-length string is one chunk: point into the input, which
     * outlives the .Call, rather than measure and copy it. Callers use the
     * length, never a terminator. */
    if (cbor_value_is_length_known(it)) {
        const char *p;
        (void) cbor_value_begin_string_iteration(it);
        err = cbor_value_get_text_string_chunk(it, &p, &len, it);
        if (err)
            internal(b, err, at);
        err = cbor_value_finish_string_iteration(it);
        if (err)
            internal(b, err, at);
        *n = len;
        return p;
    }
    err = cbor_value_calculate_string_length(it, &len);
    if (err)
        internal(b, err, at);
    char *buf = (char *) R_alloc(len + 1, 1);
    size_t cap = len + 1;
    err = cbor_value_copy_text_string(it, buf, &cap, it);
    if (err)
        internal(b, err, at);
    *n = len;
    return buf;
}

static SEXP read_bytes(zu_builder *b, CborValue *it)
{
    const uint8_t *at = cbor_value_get_next_byte(it);
    size_t len;
    CborError err = cbor_value_calculate_string_length(it, &len);
    if (err)
        internal(b, err, at);
    if (len > (size_t) R_XLEN_T_MAX)
        fail_build(b, ZU_ERR_STRING_TOO_LONG, "byte string longer than an R vector can be", at);
    SEXP out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) len));
    size_t cap = len;
    err = cbor_value_copy_byte_string(it, RAW(out), &cap, it);
    if (err)
        internal(b, err, at);
    UNPROTECT(1);
    return out;
}

static double read_float(CborValue *it)
{
    double d = 0;
    switch (cbor_value_get_type(it)) {
    case CborHalfFloatType: {
        uint16_t h;
        cbor_value_get_half_float(it, &h);
        d = zu_half_to_double(h);
        break;
    }
    case CborFloatType: {
        float f;
        cbor_value_get_float(it, &f);
        d = f;
        break;
    }
    default:
        cbor_value_get_double(it, &d);
    }
    return d;
}

static void advance(zu_builder *b, CborValue *it, const uint8_t *at)
{
    CborError err = cbor_value_advance_fixed(it);
    if (err)
        internal(b, err, at);
}

/* ---- tags ------------------------------------------------------------------------ */

static SEXP make_tag(zu_builder *b, CborTag tag, SEXP value, const uint8_t *at)
{
    PROTECT(value);
    if (tag > (UINT64_C(1) << 53))
        fail_build(b, ZU_ERR_TAG_TOO_LARGE, "tag number beyond 2^53", at);
    const char *names[] = {"tag", "value", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_ScalarReal((double) tag));
    SET_VECTOR_ELT(out, 1, value);
    Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("cbor_tag"));
    UNPROTECT(2);
    return out;
}

/* Tag 2 or 3 with its byte string (design section 6.6). */
static SEXP bignum(zu_builder *b, CborTag tag, CborValue *it, int *kind, const uint8_t *at)
{
    SEXP bytes = PROTECT(read_bytes(b, it));
    size_t n = (size_t) XLENGTH(bytes);
    const uint8_t *p = RAW(bytes);
    int negative = tag == 3;
    SEXP out;

    if (n > ZU_BIGNUM_MAX_BYTES) {
        *kind = K_OTHER;
        out = make_tag(b, tag, bytes, at);
        UNPROTECT(1);
        return out;
    }
    while (n && *p == 0) {
        p++;
        n--;
    }
    if (n <= 8) {
        uint64_t v = 0;
        for (size_t i = 0; i < n; i++)
            v = (v << 8) | p[i];
        out = integer_value(b, v, negative, kind, at);
        UNPROTECT(1);
        return out;
    }
    /* Beyond 2^64, so beyond 2^53: big_integers decides. */
    if (b->big_integers == BIG_ERROR)
        fail_build(b, ZU_ERR_BIG_INTEGER, "bignum beyond 2^53 with big_integers = \"error\"", at);
    const char *dec = zu_magnitude_to_dec(p, n, negative, negative);
    if (b->big_integers == BIG_DOUBLE) {
        *kind = K_INTDBL;
        /* strtod(), not R_strtod(): the C library's is correctly rounded;
         * R's is not where long double is only a double (macOS arm64). R
         * keeps LC_NUMERIC at "C", so the decimal point is '.'. */
        out = Rf_ScalarReal(strtod(dec, NULL));
    } else {
        *kind = K_BIGINT;
        out = scalar_bigint(dec);
    }
    UNPROTECT(1);
    return out;
}

/* The caller's handler for this tag, or R_NilValue. Handler names are
 * whole numbers up to 2^53, so a larger tag, which a double would round,
 * has none. */
static SEXP find_handler(const zu_builder *b, CborTag tag)
{
    if (!b->n_handlers || tag > (UINT64_C(1) << 53))
        return R_NilValue;
    double t = (double) tag;
    R_xlen_t lo = 0, hi = b->n_handlers;
    while (lo < hi) {
        R_xlen_t mid = lo + (hi - lo) / 2;
        if (b->handler_tags[mid] < t)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo < b->n_handlers && b->handler_tags[lo] == t ? VECTOR_ELT(b->handlers, lo)
                                                          : R_NilValue;
}

/* zu_run_handler(handler, value, tag, call) in R, which wraps an error as
 * zucbor_handler_error. User code runs here, in the middle of the build:
 * that is safe because everything the build holds is PROTECTed or
 * R_alloc()ed (design section 12), and the input was checked whole before
 * the first handler ran. The arguments are bound in a fresh environment,
 * so nothing is evaluated twice and a traceback shows names, not values. */
static SEXP run_handler(zu_builder *b, SEXP handler, CborTag tag, SEXP value)
{
    PROTECT(value);
    SEXP env = PROTECT(R_NewEnv(b->ns, FALSE, 4));
    SEXP s_handler = Rf_install("handler"), s_value = Rf_install("value");
    SEXP s_tag = Rf_install("tag"), s_call = Rf_install("call");
    Rf_defineVar(s_handler, handler, env);
    Rf_defineVar(s_value, value, env);
    SEXP t = PROTECT(Rf_ScalarReal((double) tag));
    Rf_defineVar(s_tag, t, env);
    Rf_defineVar(s_call, b->call, env);
    SEXP expr = PROTECT(Rf_lang5(Rf_install("zu_run_handler"), s_handler, s_value, s_tag, s_call));
    SEXP out = Rf_eval(expr, env);
    UNPROTECT(4);
    return out;
}

static SEXP build_tag(zu_builder *b, CborValue *it, int *kind)
{
    const uint8_t *at = cbor_value_get_next_byte(it);
    CborTag tag;
    cbor_value_get_tag(it, &tag);
    advance(b, it, at);

    /* A handler wins over the conversions below and over tags = "keep". It
     * gets the content as decoded with the same options. */
    SEXP handler = find_handler(b, tag);
    if (handler != R_NilValue) {
        int inner;
        SEXP value = build(b, it, &inner);
        *kind = K_OTHER;
        return run_handler(b, handler, tag, value);
    }

    if (b->tags == TAGS_KEEP) {
        int inner;
        SEXP value = build(b, it, &inner);
        *kind = K_OTHER;
        return make_tag(b, tag, value, at);
    }

    CborType type = cbor_value_get_type(it);
    switch (tag) {
    case 55799:
        return build(b, it, kind);
    case 0: {
        size_t n;
        const char *s = read_text(b, it, &n);
        double secs;
        if (zu_parse_rfc3339(s, n, &secs))
            fail_build(b, ZU_ERR_INVALID_DATE, "tag 0 content is not an RFC 3339 date/time", at);
        *kind = K_POSIXCT;
        return classed_real(secs, NULL, 1);
    }
    case 1: {
        double secs;
        if (type == CborIntegerType) {
            uint64_t raw;
            cbor_value_get_raw_integer(it, &raw);
            secs = cbor_value_is_negative_integer(it) ? -1.0 - (double) raw : (double) raw;
        } else {
            secs = read_float(it);
        }
        advance(b, it, at);
        *kind = K_POSIXCT;
        return classed_real(secs, NULL, 1);
    }
    case 2:
    case 3:
        return bignum(b, tag, it, kind, at);
    case 100: {
        uint64_t raw;
        cbor_value_get_raw_integer(it, &raw);
        double days = cbor_value_is_negative_integer(it) ? -1.0 - (double) raw : (double) raw;
        advance(b, it, at);
        *kind = K_DATE;
        return classed_real(days, "Date", 0);
    }
    case 1004: {
        size_t n;
        const char *s = read_text(b, it, &n);
        double days;
        if (zu_parse_full_date(s, n, &days))
            fail_build(b, ZU_ERR_INVALID_DATE, "tag 1004 content is not an RFC 3339 full-date", at);
        *kind = K_DATE;
        return classed_real(days, "Date", 0);
    }
    default: {
        int inner;
        SEXP value = build(b, it, &inner);
        *kind = K_OTHER;
        return make_tag(b, tag, value, at);
    }
    }
}

/* ---- arrays ---------------------------------------------------------------------- */

/* Marks a one-element array that simplified to a vector with I(), so that
 * cbor_encode() writes it back as an array rather than unboxing it: CBOR ->
 * R -> CBOR is then a fixed point (design section 6.3). */
static SEXP as_is(SEXP x)
{
    if (XLENGTH(x) != 1)
        return x;
    PROTECT(x);
    /* Reachable through x, but PROTECTed anyway: rchk cannot see
     * reachability through an attribute (zujson learned this first). */
    SEXP old = PROTECT(Rf_getAttrib(x, R_ClassSymbol));
    R_xlen_t n = old == R_NilValue ? 0 : XLENGTH(old);
    SEXP klass = PROTECT(Rf_allocVector(STRSXP, n + 1));
    SET_STRING_ELT(klass, 0, Rf_mkChar("AsIs"));
    for (R_xlen_t i = 0; i < n; i++)
        SET_STRING_ELT(klass, i + 1, STRING_ELT(old, i));
    Rf_setAttrib(x, R_ClassSymbol, klass);
    UNPROTECT(3);
    return x;
}

/* An array's elements, staged. Scalars go into C buffers and cost no R
 * allocation; containers, tags and byte strings are built as R values into
 * `list`. Most arrays simplify to an atomic vector (design section 6.3), so
 * most never need a SEXP per element: Stage 8 measured that as the largest
 * cost of decoding. */
typedef struct {
    R_xlen_t n;
    int *kinds;
    double *num;            /* K_INT, K_INTDBL, K_FLOAT (exact for all three) */
    int *lgl;               /* K_LGL */
    SEXP strs;              /* K_STR, as CHARSXPs; allocated on first use */
    SEXP list;              /* elements built as R values; allocated on first use */
    char *built;            /* nonzero: element i is in list */
} zu_stage;

static SEXP stage_scalar(const zu_stage *st, R_xlen_t i)
{
    switch (st->kinds[i]) {
    case K_INT:
        return Rf_ScalarInteger((int) st->num[i]);
    case K_INTDBL:
    case K_FLOAT:
        return Rf_ScalarReal(st->num[i]);
    case K_LGL:
        return Rf_ScalarLogical(st->lgl[i]);
    case K_STR:
        return Rf_ScalarString(STRING_ELT(st->strs, i));
    default:
        return R_NilValue;
    }
}

static double stage_num(const zu_stage *st, R_xlen_t i)
{
    if (!st->built[i])
        return st->num[i];
    SEXP e = VECTOR_ELT(st->list, i);
    return TYPEOF(e) == INTSXP ? (double) INTEGER(e)[0] : REAL(e)[0];
}

static SEXP stage_charsxp(const zu_stage *st, R_xlen_t i)
{
    return st->built[i] ? STRING_ELT(VECTOR_ELT(st->list, i), 0) : STRING_ELT(st->strs, i);
}

static SEXP decimal_of(const zu_stage *st, R_xlen_t i)
{
    if (st->kinds[i] == K_BIGINT)
        return STRING_ELT(VECTOR_ELT(st->list, i), 0);
    double v = stage_num(st, i);   /* integer-valued, |v| <= 2^53 */
    char dec[24];
    if (v < 0) {
        dec[0] = '-';
        zu_u64_to_dec((uint64_t)(-v), dec + 1);
    } else {
        zu_u64_to_dec((uint64_t) v, dec);
    }
    return Rf_mkChar(dec);
}

/* The staged elements as a list: every element an R value. */
static SEXP stage_list(zu_stage *st)
{
    if (st->list == R_NilValue)
        st->list = Rf_allocVector(VECSXP, st->n);
    PROTECT(st->list);
    for (R_xlen_t i = 0; i < st->n; i++)
        if (!st->built[i] && st->kinds[i] != K_NULL)
            SET_VECTOR_ELT(st->list, i, stage_scalar(st, i));
    UNPROTECT(1);
    return st->list;
}

/* The array lattice, design section 6.3: an atomic vector when the
 * elements agree, the list otherwise. NULL means "a list". */
static SEXP simplify_staged(const zu_stage *st)
{
    R_xlen_t n = st->n;
    const int *kinds = st->kinds;
    int has[K_COUNT] = {0};
    for (R_xlen_t i = 0; i < n; i++)
        has[kinds[i]] = 1;

    if (n == 0)
        return Rf_allocVector(LGLSXP, 0);
    if (has[K_OTHER])
        return R_NilValue;

    /* Logical is a kind of its own: [false, 1.5] is a list, not c(0, 1.5),
     * since a boolean is not a number in CBOR (design section 6.3). */
    int numeric = has[K_INT] || has[K_INTDBL] || has[K_FLOAT];
    int others = has[K_LGL] + has[K_BIGINT] + has[K_STR] + has[K_POSIXCT] + has[K_DATE];
    SEXP out;

    if (!numeric && !others) {                          /* all null */
        out = Rf_allocVector(LGLSXP, n);
        for (R_xlen_t i = 0; i < n; i++)
            LOGICAL(out)[i] = NA_LOGICAL;
        return out;
    }
    if (has[K_LGL] && !numeric && others == 1) {
        out = Rf_allocVector(LGLSXP, n);
        for (R_xlen_t i = 0; i < n; i++)
            LOGICAL(out)[i] = kinds[i] == K_NULL ? NA_LOGICAL
                              : st->built[i] ? LOGICAL(VECTOR_ELT(st->list, i))[0] : st->lgl[i];
        return out;
    }
    if (numeric && !others) {
        int real = has[K_INTDBL] || has[K_FLOAT];
        out = Rf_allocVector(real ? REALSXP : INTSXP, n);
        for (R_xlen_t i = 0; i < n; i++) {
            if (real)
                REAL(out)[i] = kinds[i] == K_NULL ? NA_REAL : stage_num(st, i);
            else
                INTEGER(out)[i] = kinds[i] == K_NULL ? NA_INTEGER : (int) stage_num(st, i);
        }
        return out;
    }
    /* Integer-valued items and at least one wide integer: all exact. */
    if (has[K_BIGINT] && !has[K_FLOAT] && others == 1) {
        out = PROTECT(Rf_allocVector(STRSXP, n));
        for (R_xlen_t i = 0; i < n; i++)
            SET_STRING_ELT(out, i, kinds[i] == K_NULL ? NA_STRING : decimal_of(st, i));
        Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("cbor_bigint"));
        UNPROTECT(1);
        return out;
    }
    if (numeric || others != 1)
        return R_NilValue;
    if (has[K_STR]) {
        out = PROTECT(Rf_allocVector(STRSXP, n));
        for (R_xlen_t i = 0; i < n; i++)
            SET_STRING_ELT(out, i, kinds[i] == K_NULL ? NA_STRING : stage_charsxp(st, i));
        UNPROTECT(1);
        return out;
    }
    /* POSIXct or Date: always built, as tags; keep the first's attributes. */
    int want = has[K_POSIXCT] ? K_POSIXCT : K_DATE;
    SEXP proto = R_NilValue;
    out = PROTECT(Rf_allocVector(REALSXP, n));
    for (R_xlen_t i = 0; i < n; i++) {
        if (kinds[i] == want) {
            REAL(out)[i] = REAL(VECTOR_ELT(st->list, i))[0];
            if (proto == R_NilValue)
                proto = VECTOR_ELT(st->list, i);
        } else {
            REAL(out)[i] = NA_REAL;
        }
    }
    DUPLICATE_ATTRIB(out, proto);
    UNPROTECT(1);
    return out;
}

static size_t next_count(zu_builder *b, const uint8_t *at)
{
    if (b->next_count >= b->plan->n)
        fail_build(b, "CborErrorInternalError", "container plan exhausted", at);
    return b->plan->counts[b->next_count++];
}

static SEXP build_array(zu_builder *b, CborValue *it, int *kind)
{
    const uint8_t *at = cbor_value_get_next_byte(it);
    zu_stage st;
    st.n = (R_xlen_t) next_count(b, at);
    size_t m = (size_t) st.n + 1;
    st.kinds = (int *) R_alloc(m, sizeof(int));
    st.num = (double *) R_alloc(m, sizeof(double));
    st.lgl = (int *) R_alloc(m, sizeof(int));
    st.built = (char *) R_alloc(m, 1);
    memset(st.built, 0, m);
    st.strs = R_NilValue;
    st.list = R_NilValue;
    PROTECT_INDEX strs_ix, list_ix;
    PROTECT_WITH_INDEX(st.strs, &strs_ix);
    PROTECT_WITH_INDEX(st.list, &list_ix);

    CborValue child;
    CborError err = cbor_value_enter_container(it, &child);
    if (err)
        internal(b, err, at);
    for (R_xlen_t i = 0; i < st.n; i++) {
        const uint8_t *el = cbor_value_get_next_byte(&child);
        CborType type = cbor_value_get_type(&child);
        int staged = 1;
        switch (type) {
        case CborIntegerType: {
            uint64_t raw;
            cbor_value_get_raw_integer(&child, &raw);
            int neg = cbor_value_is_negative_integer(&child);
            const uint64_t two53 = UINT64_C(1) << 53;
            if (!neg ? raw <= (uint64_t) INT_MAX : raw <= (uint64_t) INT_MAX - 1) {
                st.kinds[i] = K_INT;
                st.num[i] = neg ? -1.0 - (double) raw : (double) raw;
            } else if (!neg ? raw <= two53 : raw <= two53 - 1) {
                st.kinds[i] = K_INTDBL;
                st.num[i] = neg ? -1.0 - (double) raw : (double) raw;
            } else {
                staged = 0;         /* wide: big_integers decides, in build() */
            }
            if (staged)
                advance(b, &child, el);
            break;
        }
        case CborHalfFloatType:
        case CborFloatType:
        case CborDoubleType:
            st.kinds[i] = K_FLOAT;
            st.num[i] = read_float(&child);
            advance(b, &child, el);
            break;
        case CborBooleanType: {
            bool v;
            cbor_value_get_boolean(&child, &v);
            st.kinds[i] = K_LGL;
            st.lgl[i] = v;
            advance(b, &child, el);
            break;
        }
        case CborNullType:
        case CborUndefinedType:
            st.kinds[i] = K_NULL;
            advance(b, &child, el);
            break;
        case CborTextStringType: {
            size_t len;
            const char *s = read_text(b, &child, &len);
            if (st.strs == R_NilValue) {
                st.strs = Rf_allocVector(STRSXP, st.n);
                REPROTECT(st.strs, strs_ix);
            }
            SET_STRING_ELT(st.strs, i, zu_mkchar(b, s, len, el));
            st.kinds[i] = K_STR;
            break;
        }
        default:
            staged = 0;
        }
        if (staged) {
            if (++b->items % ZU_INTERRUPT_EVERY == 0)
                R_CheckUserInterrupt();
            continue;
        }
        if (st.list == R_NilValue) {
            st.list = Rf_allocVector(VECSXP, st.n);
            REPROTECT(st.list, list_ix);
        }
        SET_VECTOR_ELT(st.list, i, build(b, &child, &st.kinds[i]));
        st.built[i] = 1;
    }
    err = cbor_value_leave_container(it, &child);
    if (err)
        internal(b, err, at);

    SEXP out = b->simplify == SIMPLIFY_PRESERVE ? simplify_staged(&st) : R_NilValue;
    if (out == R_NilValue)
        out = stage_list(&st);
    else
        out = as_is(out);
    *kind = K_OTHER;
    UNPROTECT(2);
    return out;
}

/* ---- maps ------------------------------------------------------------------------ */

static int charsxp_cmp(const void *a, const void *b)
{
    SEXP x = *(const SEXP *) a, y = *(const SEXP *) b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

/* R caches CHARSXPs, so equal UTF-8 names are the same pointer. The
 * pointers are R's, not the input's, so qsort()'s worst case is not the
 * adversary's to choose. */
static int any_duplicated(SEXP names, R_xlen_t n)
{
    if (n < 2)
        return 0;
    SEXP *p = (SEXP *) R_alloc((size_t) n, sizeof(SEXP));
    for (R_xlen_t i = 0; i < n; i++)
        p[i] = STRING_ELT(names, i);
    qsort(p, (size_t) n, sizeof(SEXP), charsxp_cmp);
    for (R_xlen_t i = 1; i < n; i++)
        if (p[i] == p[i - 1])
            return 1;
    return 0;
}

static SEXP make_map(SEXP keys, SEXP values)
{
    const char *names[] = {"keys", "values", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, keys);
    SET_VECTOR_ELT(out, 1, values);
    Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("cbor_map"));
    UNPROTECT(1);
    return out;
}

static SEXP build_map(zu_builder *b, CborValue *it, int *kind)
{
    const uint8_t *at = cbor_value_get_next_byte(it);
    R_xlen_t n = (R_xlen_t) next_count(b, at);
    SEXP values = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
    /* The keys as R values, needed only for a cbor_map: built the first time
     * a key is not plain text (or always, under map_keys = "map"). Plain
     * text keys, the common case, go straight into names. */
    SEXP keys = R_NilValue;
    PROTECT_INDEX keys_ix;
    PROTECT_WITH_INDEX(keys, &keys_ix);
    int faithful = b->map_keys != KEYS_MAP;
    CborValue child;
    int key_kind, value_kind;
    CborError err = cbor_value_enter_container(it, &child);
    if (err)
        internal(b, err, at);
    for (R_xlen_t i = 0; i < n; i++) {
        const uint8_t *key_start = cbor_value_get_next_byte(&child);
        if (keys == R_NilValue && b->map_keys != KEYS_MAP && cbor_value_is_text_string(&child)) {
            size_t len;
            if (++b->items % ZU_INTERRUPT_EVERY == 0)
                R_CheckUserInterrupt();
            const char *s = read_text(b, &child, &len);
            SET_STRING_ELT(names, i, zu_mkchar(b, s, len, key_start));
            if (len == 0)
                faithful = 0;       /* R reads "" as no name */
        } else {
            if (keys == R_NilValue) {
                keys = Rf_allocVector(VECSXP, n);
                REPROTECT(keys, keys_ix);
                for (R_xlen_t k = 0; k < i; k++)
                    SET_VECTOR_ELT(keys, k, Rf_ScalarString(STRING_ELT(names, k)));
            }
            CborValue key_at = child;
            SEXP key = build(b, &child, &key_kind);
            SET_VECTOR_ELT(keys, i, key);
            if (key_kind == K_STR) {
                SET_STRING_ELT(names, i, STRING_ELT(key, 0));
                if (LENGTH(STRING_ELT(key, 0)) == 0)
                    faithful = 0;
            } else if (b->map_keys == KEYS_STRING) {
                size_t len;
                const char *d = zu_diagnose_item(&key_at, &len);
                SET_STRING_ELT(names, i, zu_mkchar(b, d, len, key_start));
            } else {
                faithful = 0;
            }
        }
        SET_VECTOR_ELT(values, i, build(b, &child, &value_kind));
    }
    err = cbor_value_leave_container(it, &child);
    if (err)
        internal(b, err, at);
    *kind = K_OTHER;

    if (b->map_keys == KEYS_STRING) {
        /* Stringifying may make distinct keys equal: "1" and 1 both become
         * the name "1". That is refused whatever duplicate_keys says, since
         * a named list cannot say which entry was which (design 6.4). */
        if (any_duplicated(names, n))
            fail_build(b, ZU_ERR_KEY_COLLISION, NULL, at);
    } else if (faithful && b->duplicate_keys && any_duplicated(names, n)) {
        faithful = 0;
    }

    SEXP out;
    if (faithful || b->map_keys == KEYS_STRING) {
        Rf_setAttrib(values, R_NamesSymbol, names);
        out = values;
    } else {
        if (keys == R_NilValue) {       /* every key was text, but not faithful */
            keys = Rf_allocVector(VECSXP, n);
            REPROTECT(keys, keys_ix);
            for (R_xlen_t k = 0; k < n; k++)
                SET_VECTOR_ELT(keys, k, Rf_ScalarString(STRING_ELT(names, k)));
        }
        out = make_map(keys, values);
    }
    UNPROTECT(3);
    return out;
}

/* ---- dispatch ---------------------------------------------------------------------- */

static SEXP build(zu_builder *b, CborValue *it, int *kind)
{
    const uint8_t *at = cbor_value_get_next_byte(it);
    if (++b->items % ZU_INTERRUPT_EVERY == 0)
        R_CheckUserInterrupt();

    switch (cbor_value_get_type(it)) {
    case CborArrayType:
        return build_array(b, it, kind);
    case CborMapType:
        return build_map(b, it, kind);
    case CborTagType:
        return build_tag(b, it, kind);
    case CborTextStringType: {
        size_t n;
        const char *s = read_text(b, it, &n);
        SEXP out = PROTECT(Rf_allocVector(STRSXP, 1));
        SET_STRING_ELT(out, 0, zu_mkchar(b, s, n, at));
        *kind = K_STR;
        UNPROTECT(1);
        return out;
    }
    case CborByteStringType:
        *kind = K_OTHER;
        return read_bytes(b, it);
    case CborIntegerType: {
        uint64_t raw;
        cbor_value_get_raw_integer(it, &raw);
        int negative = cbor_value_is_negative_integer(it);
        advance(b, it, at);
        return integer_value(b, raw, negative, kind, at);
    }
    case CborHalfFloatType:
    case CborFloatType:
    case CborDoubleType: {
        double d = read_float(it);
        advance(b, it, at);
        *kind = K_FLOAT;
        return Rf_ScalarReal(d);
    }
    case CborBooleanType: {
        bool v;
        cbor_value_get_boolean(it, &v);
        advance(b, it, at);
        *kind = K_LGL;
        return Rf_ScalarLogical(v);
    }
    case CborNullType:
    case CborUndefinedType:
        advance(b, it, at);
        *kind = K_NULL;
        return R_NilValue;
    case CborSimpleType: {
        uint8_t v;
        cbor_value_get_simple_type(it, &v);
        advance(b, it, at);
        SEXP out = PROTECT(Rf_ScalarInteger(v));
        Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("cbor_simple"));
        *kind = K_OTHER;
        UNPROTECT(1);
        return out;
    }
    default:
        internal(b, CborErrorUnknownType, at);
        return R_NilValue;
    }
}

/* ---- entry point ------------------------------------------------------------------- */

/* opts: mode (0 one item, 1 a sequence, 2 a prefix), deterministic,
 * duplicate_keys, max_depth, simplify, map_keys, tags, big_integers
 * (integer codes, validated in R). handlers
 * are the caller's tag handlers, or NULL.
 * Returns list(fault, value, consumed): a check-phase fault is returned for R to
 * raise with the user's call; a build-phase one is raised from here. */
SEXP zucbor_decode(SEXP x, SEXP opts, SEXP max_items, SEXP call, SEXP handlers)
{
    if (TYPEOF(x) != RAWSXP || TYPEOF(opts) != INTSXP || XLENGTH(opts) != 8)
        Rf_error("zucbor_decode: arguments must be validated in R");
    /* handlers: NULL, or list(tags, functions, namespace), from R. */
    if (handlers != R_NilValue
        && (TYPEOF(handlers) != VECSXP || XLENGTH(handlers) != 3
            || TYPEOF(VECTOR_ELT(handlers, 0)) != REALSXP
            || TYPEOF(VECTOR_ELT(handlers, 1)) != VECSXP
            || XLENGTH(VECTOR_ELT(handlers, 0)) != XLENGTH(VECTOR_ELT(handlers, 1))
            || TYPEOF(VECTOR_ELT(handlers, 2)) != ENVSXP))
        Rf_error("zucbor_decode: arguments must be validated in R");
    const int *o = INTEGER(opts);
    zu_check_opts opt;
    if (o[0] < 0 || o[0] > 2)
        Rf_error("zucbor_decode: arguments must be validated in R");
    opt.sequence = o[0] == 1;
    opt.prefix = o[0] == 2;
    opt.deterministic = o[1];
    opt.duplicate_keys = o[2];
    opt.max_depth = o[3];
    double mi = Rf_asReal(max_items);
    if (opt.max_depth < 1 || opt.max_depth > ZU_MAX_DEPTH_CAP || ISNAN(mi) || mi < 1)
        Rf_error("zucbor_decode: limits must be validated in R");
    opt.max_items = R_FINITE(mi) ? (uint64_t) mi : UINT64_MAX;

    const uint8_t *buf = RAW(x);
    size_t len = (size_t) XLENGTH(x);
    zu_plan plan;
    zu_fault fault;
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
    if (zu_check(buf, len, &opt, &plan, &fault)) {
        SET_VECTOR_ELT(out, 0, zu_fault_sexp(&fault));
        UNPROTECT(1);
        return out;
    }

    zu_builder b;
    memset(&b, 0, sizeof b);
    b.buf = buf;
    b.plan = &plan;
    b.duplicate_keys = opt.duplicate_keys;
    b.simplify = o[4];
    b.map_keys = o[5];
    b.tags = o[6];
    b.big_integers = o[7];
    b.call = call;
    if (handlers != R_NilValue) {
        b.handler_tags = REAL(VECTOR_ELT(handlers, 0));
        b.n_handlers = XLENGTH(VECTOR_ELT(handlers, 0));
        b.handlers = VECTOR_ELT(handlers, 1);
        b.ns = VECTOR_ELT(handlers, 2);
    }

    if (!opt.sequence) {
        CborParser parser;
        CborValue it;
        int kind;
        cbor_parser_init(buf, len, 0, &parser, &it);
        SET_VECTOR_ELT(out, 1, build(&b, &it, &kind));
        SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double) plan.consumed));
    } else {
        SEXP items = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) plan.n_items));
        SET_VECTOR_ELT(out, 1, items);
        size_t pos = 0;
        for (size_t i = 0; i < plan.n_items; i++) {
            CborParser parser;
            CborValue it;
            int kind;
            cbor_parser_init(buf + pos, len - pos, 0, &parser, &it);
            SET_VECTOR_ELT(items, (R_xlen_t) i, build(&b, &it, &kind));
            pos = (size_t)(cbor_value_get_next_byte(&it) - buf);
        }
        UNPROTECT(1);
    }
    UNPROTECT(1);
    return out;
}
