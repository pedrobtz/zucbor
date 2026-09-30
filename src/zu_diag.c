/* RFC 8949 section 8 diagnostic notation, in project code (design section
 * 5; roadmap Stage 5). TinyCBOR's printer always marks a float's width --
 * "1.5f16", or "1.5_1" -- and has no flag to leave it out, so it cannot
 * produce the notation RFC 8949's own Appendix A uses. This does, exactly:
 *
 *  - numbers as JavaScript prints them (shortest round-trip digits, fixed
 *    notation from 1e-7 up to 1e21, else an exponent), with ".0" added when
 *    there is no decimal point, so a float never reads as an integer;
 *  - text as JSON strings, ASCII only: non-ASCII as \u escapes, UTF-16
 *    surrogate pairs above U+FFFF, as Appendix A writes "𐅑";
 *  - "_ " after the opening bracket of an indefinite-length item.
 *
 * It runs only on input the check phase accepted, so the recursion is no
 * deeper than max_depth. Output goes to R_alloc() scratch. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zu_cbor.h"

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

static void emit(zu_text *t, const char *s, size_t n)
{
    reserve(t, n);
    memcpy(t->buf + t->len, s, n);
    t->len += n;
    t->buf[t->len] = '\0';
}

static void emits(zu_text *t, const char *s)
{
    emit(t, s, strlen(s));
}

/* ---- numbers ------------------------------------------------------------------ */

/* Reads back digits (k of them, the first before the decimal point) and a
 * decimal exponent as a double. strtod(), not R_strtod(): the latter is not
 * correctly rounded where long double is only a double (macOS arm64). */
static double read_back(const char *digits, int k, int exp10)
{
    char s[48];
    int n = 0;
    s[n++] = digits[0];
    s[n++] = '.';
    for (int i = 1; i < k; i++)
        s[n++] = digits[i];
    if (k == 1)
        s[n++] = '0';
    snprintf(s + n, sizeof s - (size_t) n, "e%d", exp10);
    return strtod(s, NULL);
}

/* Adds +1 or -1 to the last of k digits, carrying; the leading digit may
 * change the exponent. Returns 0 if the result would lose a digit. */
static int nudge(char *digits, int k, int *exp10, int dir)
{
    int i = k - 1;
    while (i >= 0) {
        int v = digits[i] - '0' + dir;
        if (v >= 0 && v <= 9) {
            digits[i] = (char)('0' + v);
            break;
        }
        digits[i] = dir > 0 ? '0' : '9';
        i--;
    }
    if (i < 0) {
        if (dir < 0)
            return 0;
        memmove(digits + 1, digits, (size_t) k);    /* 99 + 1 = 100 */
        digits[0] = '1';
        digits[k] = '\0';
        (*exp10)++;
    }
    if (digits[0] == '0')
        return 0;
    return 1;
}

/* The fewest significant digits that read back as a (> 0, finite): the
 * shortest round-trip form. printf's correctly rounded "%.*e" can miss it at
 * a tie -- 2^-24 is exactly 5.9604644775390625e-8, and at 16 digits printf
 * rounds the tie to ...062, which reads back as the neighbouring double,
 * while ...063 reads back exactly. So each precision tries both neighbours
 * of printf's answer too. Trailing zeros are removed. */
static void shortest_digits(double a, char *digits, int *k_out, int *exp_out)
{
    char e[40];
    for (int prec = 0; prec <= 16; prec++) {
        snprintf(e, sizeof e, "%.*e", prec, a);
        char base[24];
        int k = 0;
        const char *p = e;
        for (; *p && *p != 'e'; p++)
            if (*p >= '0' && *p <= '9')
                base[k++] = *p;
        base[k] = '\0';
        int exp10 = atoi(p + 1);
        int found = read_back(base, k, exp10) == a;
        if (!found) {
            for (int dir = 1; dir >= -1 && !found; dir -= 2) {
                char alt[24];
                int alt_exp = exp10;
                memcpy(alt, base, (size_t) k + 1);
                if (nudge(alt, k, &alt_exp, dir) && read_back(alt, k, alt_exp) == a) {
                    memcpy(base, alt, (size_t) k + 1);
                    exp10 = alt_exp;
                    found = 1;
                }
            }
        }
        if (found || prec == 16) {
            while (k > 1 && base[k - 1] == '0')
                base[--k] = '\0';
            memcpy(digits, base, (size_t) k + 1);
            *k_out = k;
            *exp_out = exp10;
            return;
        }
    }
}

/* d as RFC 8949 Appendix A prints it, into buf (at least 40 bytes). */
void zu_format_double(double d, char *buf)
{
    if (isnan(d)) {
        strcpy(buf, "NaN");
        return;
    }
    if (isinf(d)) {
        strcpy(buf, d > 0 ? "Infinity" : "-Infinity");
        return;
    }
    if (d == 0) {
        strcpy(buf, signbit(d) ? "-0.0" : "0.0");
        return;
    }
    char digits[24];
    int k, exp10;
    shortest_digits(fabs(d), digits, &k, &exp10);
    int n = exp10 + 1;          /* value = 0.DIGITS * 10^n */

    char *o = buf;
    if (d < 0)
        *o++ = '-';
    if (k <= n && n <= 21) {
        memcpy(o, digits, (size_t) k);
        o += k;
        for (int i = k; i < n; i++)
            *o++ = '0';
        memcpy(o, ".0", 3);
    } else if (0 < n && n <= 21) {
        memcpy(o, digits, (size_t) n);
        o += n;
        *o++ = '.';
        strcpy(o, digits + n);
    } else if (-6 < n && n <= 0) {
        *o++ = '0';
        *o++ = '.';
        for (int i = 0; i < -n; i++)
            *o++ = '0';
        strcpy(o, digits);
    } else {
        *o++ = digits[0];
        *o++ = '.';
        if (k > 1) {
            memcpy(o, digits + 1, (size_t)(k - 1));
            o += k - 1;
        } else {
            *o++ = '0';
        }
        /* The exponent by hand: at most three digits, and GCC's
         * -Wformat-truncation cannot prove a snprintf() into this tail safe,
         * which R CMD check reports as a WARNING. */
        int x = n - 1;
        *o++ = 'e';
        *o++ = x < 0 ? '-' : '+';
        x = abs(x);
        char exp_digits[4];
        int nd = 0;
        do {
            exp_digits[nd++] = (char)('0' + x % 10);
            x /= 10;
        } while (x);
        while (nd)
            *o++ = exp_digits[--nd];
        *o = '\0';
    }
}

static void emit_uint(zu_text *t, uint64_t v)
{
    char buf[24];
    zu_u64_to_dec(v, buf);
    emits(t, buf);
}

/* ---- strings -------------------------------------------------------------------- */

static void emit_u16(zu_text *t, unsigned v)
{
    static const char hex[] = "0123456789abcdef";
    char buf[6] = {'\\', 'u', hex[(v >> 12) & 15], hex[(v >> 8) & 15], hex[(v >> 4) & 15], hex[v & 15]};
    emit(t, buf, 6);
}

/* A text chunk as a JSON string body. The check phase proved it is UTF-8. */
static void emit_text_body(zu_text *t, const uint8_t *s, size_t n)
{
    size_t i = 0;
    while (i < n) {
        uint8_t c = s[i];
        if (c < 0x80) {
            switch (c) {
            case '"': emits(t, "\\\""); break;
            case '\\': emits(t, "\\\\"); break;
            case '\b': emits(t, "\\b"); break;
            case '\f': emits(t, "\\f"); break;
            case '\n': emits(t, "\\n"); break;
            case '\r': emits(t, "\\r"); break;
            case '\t': emits(t, "\\t"); break;
            default:
                if (c < 0x20 || c == 0x7f)
                    emit_u16(t, c);
                else
                    emit(t, (const char *) &c, 1);
            }
            i++;
            continue;
        }
        size_t len = c >= 0xf0 ? 4 : c >= 0xe0 ? 3 : 2;
        uint32_t cp = c & (len == 2 ? 0x1f : len == 3 ? 0x0f : 0x07);
        for (size_t k = 1; k < len && i + k < n; k++)
            cp = (cp << 6) | (s[i + k] & 0x3f);
        if (cp >= 0x10000) {
            cp -= 0x10000;
            emit_u16(t, 0xd800 | (cp >> 10));
            emit_u16(t, 0xdc00 | (cp & 0x3ff));
        } else {
            emit_u16(t, cp);
        }
        i += len;
    }
}

static void emit_bytes_body(zu_text *t, const uint8_t *s, size_t n)
{
    static const char hex[] = "0123456789abcdef";
    reserve(t, 2 * n);
    for (size_t i = 0; i < n; i++) {
        t->buf[t->len++] = hex[s[i] >> 4];
        t->buf[t->len++] = hex[s[i] & 15];
    }
    t->buf[t->len] = '\0';
}

static void emit_chunk(zu_text *t, int text, const uint8_t *p, size_t n)
{
    if (text) {
        emits(t, "\"");
        emit_text_body(t, p, n);
        emits(t, "\"");
    } else {
        emits(t, "h'");
        emit_bytes_body(t, p, n);
        emits(t, "'");
    }
}

/* ---- items ------------------------------------------------------------------------ */

static void fail(CborError err)
{
    Rf_error("zucbor: diagnostic notation failed on checked input (%d)", (int) err);
}

static void emit_item(zu_text *t, CborValue *it);

static void emit_string(zu_text *t, CborValue *it)
{
    int text = cbor_value_is_text_string(it);
    int chunked = !cbor_value_is_length_known(it);
    const void *p;
    size_t n;
    int first = 1;
    CborError err;
    if (chunked)
        emits(t, "(_ ");
    (void) cbor_value_begin_string_iteration(it);
    for (;;) {
        err = text ? cbor_value_get_text_string_chunk(it, (const char **) &p, &n, it)
                   : cbor_value_get_byte_string_chunk(it, (const uint8_t **) &p, &n, it);
        if (err == CborErrorNoMoreStringChunks)
            break;
        if (err)
            fail(err);
        if (!first)
            emits(t, ", ");
        first = 0;
        emit_chunk(t, text, (const uint8_t *) p, n);
    }
    err = cbor_value_finish_string_iteration(it);
    if (err)
        fail(err);
    if (chunked)
        emits(t, ")");
}

static void emit_container(zu_text *t, CborValue *it)
{
    int map = cbor_value_is_map(it);
    int chunked = !cbor_value_is_length_known(it);
    CborValue child;
    CborError err = cbor_value_enter_container(it, &child);
    if (err)
        fail(err);
    emits(t, map ? "{" : "[");
    if (chunked)
        emits(t, "_ ");
    for (int i = 0; !cbor_value_at_end(&child); i++) {
        if (i)
            emits(t, ", ");
        emit_item(t, &child);
        if (map) {
            emits(t, ": ");
            emit_item(t, &child);
        }
    }
    emits(t, map ? "}" : "]");
    err = cbor_value_leave_container(it, &child);
    if (err)
        fail(err);
}

static void emit_item(zu_text *t, CborValue *it)
{
    CborError err = CborNoError;
    switch (cbor_value_get_type(it)) {
    case CborArrayType:
    case CborMapType:
        emit_container(t, it);
        return;
    case CborByteStringType:
    case CborTextStringType:
        emit_string(t, it);
        return;
    case CborTagType: {
        CborTag tag;
        cbor_value_get_tag(it, &tag);
        emit_uint(t, tag);
        emits(t, "(");
        err = cbor_value_advance_fixed(it);
        if (err)
            fail(err);
        emit_item(t, it);
        emits(t, ")");
        return;
    }
    case CborIntegerType: {
        uint64_t raw;
        cbor_value_get_raw_integer(it, &raw);
        if (cbor_value_is_negative_integer(it)) {
            emits(t, "-");
            if (raw == UINT64_MAX)
                emits(t, "18446744073709551616");
            else
                emit_uint(t, raw + 1);
        } else {
            emit_uint(t, raw);
        }
        break;
    }
    case CborHalfFloatType:
    case CborFloatType:
    case CborDoubleType: {
        double d;
        if (cbor_value_is_half_float(it)) {
            uint16_t h;
            cbor_value_get_half_float(it, &h);
            d = zu_half_to_double(h);
        } else if (cbor_value_is_float(it)) {
            float f;
            cbor_value_get_float(it, &f);
            d = f;
        } else {
            cbor_value_get_double(it, &d);
        }
        char buf[40];
        zu_format_double(d, buf);
        emits(t, buf);
        break;
    }
    case CborBooleanType: {
        bool b;
        cbor_value_get_boolean(it, &b);
        emits(t, b ? "true" : "false");
        break;
    }
    case CborNullType:
        emits(t, "null");
        break;
    case CborUndefinedType:
        emits(t, "undefined");
        break;
    case CborSimpleType: {
        uint8_t v;
        cbor_value_get_simple_type(it, &v);
        emits(t, "simple(");
        emit_uint(t, v);
        emits(t, ")");
        break;
    }
    default:
        fail(CborErrorUnknownType);
    }
    err = cbor_value_advance_fixed(it);
    if (err)
        fail(err);
}

/* The diagnostic notation of the item at *it, which is left where it was.
 * R_alloc()ed and NUL-terminated; its length goes to *len. */
const char *zu_diagnose_item(const CborValue *it, size_t *len)
{
    zu_text t = {NULL, 0, 0};
    CborValue copy = *it;
    reserve(&t, 0);
    t.buf[0] = '\0';
    emit_item(&t, &copy);
    *len = t.len;
    return t.buf;
}

/* cbor_diagnose(): check, then print every item, comma-separated for a
 * sequence (RFC 8742 section 4.2). Returns list(fault, text) like
 * zucbor_decode(), so R raises a check fault with the user's call. */
SEXP zucbor_diagnose(SEXP x, SEXP opts, SEXP max_items)
{
    if (TYPEOF(x) != RAWSXP || TYPEOF(opts) != INTSXP || XLENGTH(opts) != 4)
        Rf_error("zucbor_diagnose: arguments must be validated in R");
    const int *o = INTEGER(opts);
    zu_check_opts opt;
    opt.sequence = o[0];
    opt.deterministic = o[1];
    opt.duplicate_keys = o[2];
    opt.max_depth = o[3];
    double mi = Rf_asReal(max_items);
    if (opt.max_depth < 1 || opt.max_depth > ZU_MAX_DEPTH_CAP || ISNAN(mi) || mi < 1)
        Rf_error("zucbor_diagnose: limits must be validated in R");
    opt.max_items = R_FINITE(mi) ? (uint64_t) mi : UINT64_MAX;

    const uint8_t *buf = RAW(x);
    size_t len = (size_t) XLENGTH(x);
    zu_plan plan;
    zu_fault fault;
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    if (zu_check(buf, len, &opt, &plan, &fault)) {
        SET_VECTOR_ELT(out, 0, zu_fault_sexp(&fault));
        UNPROTECT(1);
        return out;
    }
    zu_text t = {NULL, 0, 0};
    reserve(&t, 0);
    t.buf[0] = '\0';
    size_t pos = 0;
    for (size_t i = 0; i < plan.n_items; i++) {
        CborParser parser;
        CborValue it;
        cbor_parser_init(buf + pos, len - pos, 0, &parser, &it);
        if (i)
            emits(&t, ", ");
        emit_item(&t, &it);
        pos = (size_t)(cbor_value_get_next_byte(&it) - buf);
    }
    if (t.len > INT_MAX)
        Rf_error("zucbor: diagnostic notation longer than an R string can be");
    SEXP s = PROTECT(Rf_mkCharLenCE(t.buf, (int) t.len, CE_UTF8));
    SET_VECTOR_ELT(out, 1, Rf_ScalarString(s));
    UNPROTECT(2);
    return out;
}

/* Test hook: does each double read back exactly from its diagnostic form?
 * Uses the C library's strtod(), which is correctly rounded everywhere; R's
 * own parser is not on every platform. */
SEXP zucbor_format_roundtrip(SEXP x)
{
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(Rf_allocVector(LGLSXP, n));
    for (R_xlen_t i = 0; i < n; i++) {
        double d = REAL(x)[i];
        char buf[40];
        zu_format_double(d, buf);
        double back = strtod(buf, NULL);
        LOGICAL(out)[i] = isnan(d) ? isnan(back) : back == d && signbit(back) == signbit(d);
    }
    UNPROTECT(1);
    return out;
}
