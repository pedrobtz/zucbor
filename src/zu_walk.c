/* The check phase: design sections 4, 6.5 and 11.
 *
 * An iterative walk over TinyCBOR's iterator enforces the limits, finds
 * duplicate map keys and records each container's element count, then
 * cbor_value_validate() checks UTF-8, tag content types and, on request,
 * deterministic encoding. Nothing here allocates an R object. Scratch comes
 * from R_alloc(), which R releases when the .Call returns or unwinds, so an
 * interrupt or an allocation failure cannot leak it (design section 12).
 *
 * TinyCBOR's preconditions are cbor_assert()s that become unreachable()
 * under R's -DNDEBUG (design section 13, trap 3): every accessor below is
 * called only after the item's type has been checked. */

#include <math.h>
#include <string.h>

#include "zucbor.h"
#include "cbor.h"

/* Validity checks every read path shares (design section 11). Two checks
 * that TinyCBOR offers are the walk's instead:
 *  - trailing bytes, not CborValidateCompleteData: in a sequence the next
 *    item's bytes are not garbage;
 *  - tag content, not CborValidateTagUse: TinyCBOR 7.0's table allows only
 *    an integer under tag 1, where RFC 8949 section 3.4.2 also allows a
 *    float, so it refuses Appendix A's 1(1363896240.5). See tag_content_ok(). */
#define ZU_VALIDATE_FLAGS (CborValidateUtf8)

#define ZU_INTERRUPT_EVERY 65536u

/* Map keys are compared by value (design section 6.5). Keys of different
 * kinds are never equal: the integer 1 and the float 1.0 are different CBOR
 * values. */
enum { KEY_INT, KEY_FLOAT, KEY_SIMPLE, KEY_BYTES, KEY_TEXT, KEY_ENCODED };

typedef struct {
    const uint8_t *ptr;     /* string content, or the key's encoded bytes */
    size_t len;
    uint64_t u;             /* integer magnitude, simple value, double bits */
    size_t offset;          /* where the key starts */
    uint8_t kind;
    uint8_t negative;
} zu_key;

typedef struct {
    CborValue it;               /* iterator inside the container */
    const uint8_t *elem_start;  /* start of the element being walked */
    size_t count;               /* elements completed (keys and values) */
    size_t slot;                /* this container's plan->counts index */
    size_t key_base;            /* this map's first key descriptor */
    int tag_levels;             /* tags wrapping the container */
    uint8_t type;
} zu_frame;

typedef struct {
    const uint8_t *buf, *end;
    const zu_check_opts *opt;
    zu_fault *fault;
    zu_plan *plan;
    zu_frame *frames;
    int sp;
    int depth;
    uint64_t items;
    zu_key *keys;
    size_t n_keys, cap_keys;
} zu_walker;

/* ---- faults ---------------------------------------------------------------- */

static double offset_of(const zu_walker *w, const uint8_t *at)
{
    return at ? (double)(at - w->buf) : NA_REAL;
}

static int fail(zu_walker *w, const char *status, const char *detail,
                const uint8_t *at)
{
    w->fault->status = status;
    w->fault->detail = detail;
    w->fault->offset = offset_of(w, at);
    w->fault->limit = NULL;
    w->fault->limit_value = NA_REAL;
    return 1;
}

static int fail_cbor(zu_walker *w, CborError err, const uint8_t *at)
{
    const char *name = zu_cbor_status_name(err);
    return fail(w, name ? name : "CborUnknownError", cbor_error_string(err), at);
}

static int fail_limit(zu_walker *w, const char *status, const char *limit,
                      double value, const uint8_t *at)
{
    fail(w, status, NULL, at);
    w->fault->limit = limit;
    w->fault->limit_value = value;
    return 1;
}

/* ---- scratch ---------------------------------------------------------------- */

/* Growth by doubling into fresh R_alloc() blocks. The old block stays until
 * the .Call ends, so the waste is bounded by the final size. */
static void *grow(void *old, size_t used, size_t *cap, size_t size)
{
    size_t newcap = *cap ? *cap * 2 : 64;
    void *p = R_alloc(newcap, (int)size);
    if (used)
        memcpy(p, old, used * size);
    *cap = newcap;
    return p;
}

static int count_item(zu_walker *w, const uint8_t *at)
{
    w->items++;
    if (w->items > w->opt->max_items)
        return fail_limit(w, ZU_ERR_ITEM_LIMIT, "max_items",
                          (double)w->opt->max_items, at);
    if (w->items % ZU_INTERRUPT_EVERY == 0)
        R_CheckUserInterrupt();
    return 0;
}

/* ---- duplicate keys --------------------------------------------------------- */

static int bytes_cmp(const uint8_t *a, size_t na, const uint8_t *b, size_t nb)
{
    size_t n = na < nb ? na : nb;
    int r = n ? memcmp(a, b, n) : 0;
    if (r)
        return r;
    return na < nb ? -1 : (na > nb ? 1 : 0);
}

static int key_cmp(const zu_key *a, const zu_key *b)
{
    if (a->kind != b->kind)
        return a->kind < b->kind ? -1 : 1;
    switch (a->kind) {
    case KEY_INT:
        if (a->negative != b->negative)
            return a->negative < b->negative ? -1 : 1;
        /* fall through */
    case KEY_FLOAT:
    case KEY_SIMPLE:
        return a->u < b->u ? -1 : (a->u > b->u ? 1 : 0);
    default:
        return bytes_cmp(a->ptr, a->len, b->ptr, b->len);
    }
}

/* Bottom-up merge sort: O(n log n) on any input. A library qsort() may be
 * quadratic on an adversarial order, and the keys are the adversary's. */
static void sort_keys(zu_key *a, size_t n)
{
    zu_key *tmp = (zu_key *) R_alloc(n, sizeof(zu_key));
    zu_key *src = a, *dst = tmp;
    for (size_t width = 1; width < n; width *= 2) {
        for (size_t lo = 0; lo < n; lo += 2 * width) {
            size_t mid = lo + width < n ? lo + width : n;
            size_t hi = lo + 2 * width < n ? lo + 2 * width : n;
            size_t i = lo, j = mid, k = lo;
            while (i < mid && j < hi)
                dst[k++] = key_cmp(&src[j], &src[i]) < 0 ? src[j++] : src[i++];
            while (i < mid)
                dst[k++] = src[i++];
            while (j < hi)
                dst[k++] = src[j++];
        }
        zu_key *t = src;
        src = dst;
        dst = t;
    }
    if (src != a)
        memcpy(a, src, n * sizeof(zu_key));
}

static int check_duplicates(zu_walker *w, size_t base)
{
    size_t n = w->n_keys - base;
    if (n < 2)
        return 0;               /* and w->keys may still be NULL */
    zu_key *k = w->keys + base;
    sort_keys(k, n);
    for (size_t i = 1; i < n; i++) {
        if (key_cmp(&k[i - 1], &k[i]) == 0) {
            size_t later = k[i].offset > k[i - 1].offset ? k[i].offset : k[i - 1].offset;
            return fail(w, ZU_ERR_DUPLICATE_KEY, NULL, w->buf + later);
        }
    }
    return 0;
}

/* Nonzero if the element about to be walked is a map key whose value must
 * be recorded for duplicate detection. */
static int at_key(const zu_walker *w)
{
    if (w->opt->duplicate_keys || w->sp == 0)
        return 0;
    const zu_frame *p = &w->frames[w->sp - 1];
    return p->type == CborMapType && p->count % 2 == 0;
}

static zu_key *push_key(zu_walker *w, const uint8_t *start)
{
    if (w->n_keys == w->cap_keys)
        w->keys = (zu_key *) grow(w->keys, w->n_keys, &w->cap_keys, sizeof(zu_key));
    zu_key *k = &w->keys[w->n_keys++];
    memset(k, 0, sizeof *k);
    k->offset = (size_t)(start - w->buf);
    return k;
}

static uint64_t double_bits(double d)
{
    uint64_t u;
    if (isnan(d))
        return UINT64_C(0x7ff8000000000000);   /* every NaN is one key */
    memcpy(&u, &d, sizeof u);
    return u;
}

/* ---- the walk ----------------------------------------------------------------- */

/* The element just walked is complete; tell its container. */
static void element_done(zu_walker *w)
{
    if (w->sp)
        w->frames[w->sp - 1].count++;
}

static int open_container(zu_walker *w, CborValue *it, const uint8_t *start, int tags)
{
    int is_map = cbor_value_is_map(it);
    if (w->depth + 1 > w->opt->max_depth)
        return fail_limit(w, ZU_ERR_DEPTH_LIMIT, "max_depth", w->opt->max_depth, start);

    /* Every element costs at least one byte, so a length the rest of the
     * input cannot hold is truncation, found here before TinyCBOR is asked to
     * track it (it refuses lengths of 2^32 and over as "too large"). */
    if (cbor_value_is_length_known(it)) {
        size_t n, avail = (size_t)(w->end - start);
        CborError err = is_map ? cbor_value_get_map_length(it, &n)
                               : cbor_value_get_array_length(it, &n);
        if (err || n > avail / (is_map ? 2 : 1))
            return fail_cbor(w, CborErrorUnexpectedEOF, start);
    }

    zu_frame *f = &w->frames[w->sp];
    memset(f, 0, sizeof *f);
    f->type = (uint8_t) cbor_value_get_type(it);
    f->tag_levels = tags;
    f->key_base = w->n_keys;
    if (w->plan) {
        if (w->plan->n == w->plan->cap)
            w->plan->counts = (size_t *) grow(w->plan->counts, w->plan->n,
                                              &w->plan->cap, sizeof(size_t));
        f->slot = w->plan->n++;
    }
    CborError err = cbor_value_enter_container(it, &f->it);
    if (err)
        return fail_cbor(w, err, cbor_value_get_next_byte(&f->it));
    w->depth++;
    w->sp++;
    return 0;
}

static int close_container(zu_walker *w, CborValue *top)
{
    zu_frame *f = &w->frames[w->sp - 1];
    if (f->type == CborMapType) {
        if (f->count % 2)
            return fail(w, ZU_ERR_ODD_MAP, NULL, cbor_value_get_next_byte(&f->it));
        if (!w->opt->duplicate_keys) {
            if (check_duplicates(w, f->key_base))
                return 1;
            w->n_keys = f->key_base;
        }
    }
    if (w->plan)
        w->plan->counts[f->slot] = f->type == CborMapType ? f->count / 2 : f->count;

    CborValue *parent = w->sp > 1 ? &w->frames[w->sp - 2].it : top;
    CborError err = cbor_value_leave_container(parent, &f->it);
    if (err)
        return fail_cbor(w, err, cbor_value_get_next_byte(parent));
    w->depth -= 1 + f->tag_levels;
    w->sp--;

    /* A container that was a map key is compared by its encoded bytes. */
    if (at_key(w)) {
        zu_frame *p = &w->frames[w->sp - 1];
        zu_key *k = push_key(w, p->elem_start);
        k->kind = KEY_ENCODED;
        k->ptr = p->elem_start;
        k->len = (size_t)(cbor_value_get_next_byte(parent) - p->elem_start);
    }
    element_done(w);
    return 0;
}

/* Walks a string, counting the chunks of an indefinite-length one as items.
 * Its content is gathered when it is a map key, or the payload of a bignum
 * under deterministic = TRUE; otherwise nothing is copied. */
static int walk_string(zu_walker *w, CborValue *it, int want_content,
                       const uint8_t **content, size_t *total)
{
    int text = cbor_value_is_text_string(it);
    int chunked = !cbor_value_is_length_known(it);
    CborValue first = *it;
    const void *p;
    size_t n, chunks = 0;
    CborError err;

    *content = NULL;
    *total = 0;
    (void) cbor_value_begin_string_iteration(it);   /* cannot fail */
    for (;;) {
        err = text ? cbor_value_get_text_string_chunk(it, (const char **)&p, &n, it)
                   : cbor_value_get_byte_string_chunk(it, (const uint8_t **)&p, &n, it);
        if (err == CborErrorNoMoreStringChunks)
            break;
        if (err)
            return fail_cbor(w, err, cbor_value_get_next_byte(it));
        if (chunked && count_item(w, (const uint8_t *)p))
            return 1;
        if (!chunks)
            *content = (const uint8_t *)p;
        chunks++;
        *total += n;
    }
    err = cbor_value_finish_string_iteration(it);
    if (err)
        return fail_cbor(w, err, cbor_value_get_next_byte(it));

    /* One chunk is already contiguous in the input; more are joined. */
    if (want_content && chunks > 1) {
        uint8_t *joined = (uint8_t *) R_alloc(*total ? *total : 1, 1);
        size_t at = 0;
        (void) cbor_value_begin_string_iteration(&first);
        for (;;) {
            err = text ? cbor_value_get_text_string_chunk(&first, (const char **)&p, &n, &first)
                       : cbor_value_get_byte_string_chunk(&first, (const uint8_t **)&p, &n, &first);
            if (err)
                break;
            if (n)
                memcpy(joined + at, p, n);
            at += n;
        }
        *content = joined;
    }
    return 0;
}

/* The content types RFC 8949 and RFC 8943 require under the tags that
 * restrict them: TinyCBOR's knownTagData with two corrections -- tag 1 also
 * takes a float, and 21-23 take any item -- plus 100 and 1004, which zucbor
 * converts. A tag not listed may wrap anything. */
static int tag_content_ok(CborTag tag, CborType type)
{
    switch (tag) {
    case 0: case 32: case 33: case 34: case 35: case 36: case 1004:
        return type == CborTextStringType;
    case 1:
        return type == CborIntegerType || type == CborHalfFloatType ||
               type == CborFloatType || type == CborDoubleType;
    case 2: case 3: case 24:
        return type == CborByteStringType;
    case 4: case 5: case 16: case 17: case 18: case 96: case 97: case 98:
        return type == CborArrayType;
    case 100:
        return type == CborIntegerType;
    default:
        return 1;
    }
}

/* RFC 8949 section 3.4.3: in preferred serialization a bignum has no leading
 * zero byte, and one that fits a plain integer is not a bignum at all. */
static int check_bignum(zu_walker *w, const uint8_t *content, size_t n,
                        const uint8_t *start)
{
    if (n == 0 || content[0] == 0 || n <= 8)
        return fail(w, ZU_ERR_BIGNUM_NOT_PREFERRED, NULL, start);
    return 0;
}

static int walk_element(zu_walker *w, CborValue *it)
{
    const uint8_t *start = cbor_value_get_next_byte(it);
    int key = at_key(w);
    int tags = 0;
    CborTag tag = 0;
    CborError err;

    if (w->sp)
        w->frames[w->sp - 1].elem_start = start;

    while (cbor_value_is_tag(it)) {
        if (count_item(w, cbor_value_get_next_byte(it)))
            return 1;
        if (w->depth + 1 > w->opt->max_depth)
            return fail_limit(w, ZU_ERR_DEPTH_LIMIT, "max_depth", w->opt->max_depth,
                              cbor_value_get_next_byte(it));
        w->depth++;
        tags++;
        const uint8_t *tag_at = cbor_value_get_next_byte(it);
        cbor_value_get_tag(it, &tag);
        err = cbor_value_advance_fixed(it);
        if (err)
            return fail_cbor(w, err, cbor_value_get_next_byte(it));
        if (!tag_content_ok(tag, cbor_value_get_type(it)))
            return fail_cbor(w, CborErrorInappropriateTagForType, tag_at);
    }
    if (count_item(w, cbor_value_get_next_byte(it)))
        return 1;

    CborType type = cbor_value_get_type(it);
    if (type == CborArrayType || type == CborMapType)
        return open_container(w, it, start, tags);

    /* A tagged key is compared by its encoded bytes, like a container. */
    zu_key *k = NULL;
    if (key && !tags)
        k = push_key(w, start);

    switch (type) {
    case CborByteStringType:
    case CborTextStringType: {
        const uint8_t *content;
        size_t total;
        int bignum = w->opt->deterministic && tags && (tag == 2 || tag == 3) &&
                     type == CborByteStringType;
        if (walk_string(w, it, k != NULL || bignum, &content, &total))
            return 1;
        if (bignum && check_bignum(w, content, total, start))
            return 1;
        if (k) {
            k->kind = type == CborTextStringType ? KEY_TEXT : KEY_BYTES;
            k->ptr = content;
            k->len = total;
        }
        break;
    }
    case CborIntegerType:
        if (k) {
            k->kind = KEY_INT;
            k->negative = cbor_value_is_negative_integer(it);
            cbor_value_get_raw_integer(it, &k->u);
        }
        err = cbor_value_advance_fixed(it);
        if (err)
            return fail_cbor(w, err, cbor_value_get_next_byte(it));
        break;
    case CborHalfFloatType:
    case CborFloatType:
    case CborDoubleType:
        if (k) {
            double d;
            if (type == CborHalfFloatType) {
                uint16_t h;
                cbor_value_get_half_float(it, &h);
                d = zu_half_to_double(h);
            } else if (type == CborFloatType) {
                float f;
                cbor_value_get_float(it, &f);
                d = f;
            } else {
                cbor_value_get_double(it, &d);
            }
            k->kind = KEY_FLOAT;
            k->u = double_bits(d);
        }
        err = cbor_value_advance_fixed(it);
        if (err)
            return fail_cbor(w, err, cbor_value_get_next_byte(it));
        break;
    case CborBooleanType:
    case CborNullType:
    case CborUndefinedType:
    case CborSimpleType:
        if (k) {
            k->kind = KEY_SIMPLE;
            if (type == CborSimpleType) {
                uint8_t s;
                cbor_value_get_simple_type(it, &s);
                k->u = s;
            } else if (type == CborBooleanType) {
                bool b;
                cbor_value_get_boolean(it, &b);
                k->u = b ? 21 : 20;
            } else {
                k->u = type == CborNullType ? 22 : 23;
            }
        }
        err = cbor_value_advance_fixed(it);
        if (err)
            return fail_cbor(w, err, cbor_value_get_next_byte(it));
        break;
    default:
        return fail_cbor(w, CborErrorUnknownType, start);
    }

    if (key && tags) {
        zu_key *tk = push_key(w, start);
        tk->kind = KEY_ENCODED;
        tk->ptr = start;
        tk->len = (size_t)(cbor_value_get_next_byte(it) - start);
    }
    w->depth -= tags;
    element_done(w);
    return 0;
}

/* Walks one top-level item: iteratively, with an explicit container stack,
 * so hostile nesting cannot exhaust the C stack. */
static int walk_item(zu_walker *w, CborValue *top)
{
    w->sp = 0;
    w->depth = 0;
    for (;;) {
        if (w->sp) {
            CborValue *it = &w->frames[w->sp - 1].it;
            if (cbor_value_at_end(it)) {
                if (close_container(w, top))
                    return 1;
                if (w->sp == 0)
                    return 0;
                continue;
            }
            if (walk_element(w, it))
                return 1;
        } else {
            if (walk_element(w, top))
                return 1;
            if (w->sp == 0)
                return 0;       /* a scalar at the top */
        }
    }
}

int zu_check(const uint8_t *buf, size_t len, const zu_check_opts *opt,
             zu_plan *plan, zu_fault *fault)
{
    zu_walker w;
    memset(&w, 0, sizeof w);
    w.buf = buf;
    w.end = buf + len;
    w.opt = opt;
    w.fault = fault;
    w.plan = plan;
    w.frames = (zu_frame *) R_alloc((size_t)opt->max_depth + 1, sizeof(zu_frame));
    fault->status = NULL;
    if (plan) {
        plan->counts = NULL;
        plan->n = plan->cap = 0;
        plan->n_items = 0;
    }

    if (len == 0) {
        if (opt->sequence)
            return 0;
        return fail_cbor(&w, CborErrorUnexpectedEOF, buf);
    }

    uint32_t flags = ZU_VALIDATE_FLAGS;
    if (opt->deterministic)
        flags |= CborValidateCanonicalFormat;

    size_t pos = 0;
    while (pos < len) {
        CborParser parser;
        CborValue it;
        CborError err = cbor_parser_init(buf + pos, len - pos, 0, &parser, &it);
        if (err)
            return fail_cbor(&w, err, buf + pos);
        CborValue start = it;
        if (walk_item(&w, &it))
            return 1;
        /* Validation reports no position (design section 10). */
        err = cbor_value_validate(&start, flags);
        if (err)
            return fail_cbor(&w, err, NULL);
        pos = (size_t)(cbor_value_get_next_byte(&it) - buf);
        if (plan)
            plan->n_items++;
        if (!opt->sequence && pos < len)
            return fail_cbor(&w, CborErrorGarbageAtEnd, buf + pos);
    }
    return 0;
}

SEXP zucbor_check(SEXP x, SEXP sequence, SEXP deterministic,
                  SEXP duplicate_keys, SEXP max_depth, SEXP max_items)
{
    if (TYPEOF(x) != RAWSXP)
        Rf_error("zucbor_check: x must be a raw vector");
    zu_check_opts opt;
    opt.sequence = Rf_asLogical(sequence) == TRUE;
    opt.deterministic = Rf_asLogical(deterministic) == TRUE;
    opt.duplicate_keys = Rf_asLogical(duplicate_keys) == TRUE;
    opt.max_depth = Rf_asInteger(max_depth);
    double mi = Rf_asReal(max_items);
    if (opt.max_depth < 1 || opt.max_depth > ZU_MAX_DEPTH_CAP || ISNAN(mi) || mi < 1)
        Rf_error("zucbor_check: limits must be validated in R");
    opt.max_items = R_FINITE(mi) ? (uint64_t) mi : UINT64_MAX;

    zu_fault fault;
    if (zu_check(RAW(x), (size_t) XLENGTH(x), &opt, NULL, &fault))
        return zu_fault_sexp(&fault);
    return R_NilValue;
}
