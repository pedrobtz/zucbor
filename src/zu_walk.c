/* The check phase: design sections 4, 6.5 and 11.
 *
 * An iterative walk over TinyCBOR's iterator enforces the limits, finds
 * duplicate map keys and records each container's element count, then
 * cbor_value_validate() checks UTF-8, tag content types and, on request,
 * deterministic encoding. Nothing here allocates an R object. Scratch comes
 * from R_alloc(), which R releases when the .Call returns or unwinds, so an
 * interrupt or an allocation failure cannot leak it (design section 12).
 * No other R API is used here: built with -DZU_STANDALONE, zu_scratch() is
 * the fuzz harness's arena (zu_check.h).
 *
 * TinyCBOR's preconditions are cbor_assert()s that become unreachable()
 * under R's -DNDEBUG (design section 13, trap 3): every accessor below is
 * called only after the item's type has been checked. */

#include <math.h>
#include <string.h>

#include "zu_check.h"
#include "cbor.h"

/* Validity checks every read path shares (design section 11): none remain
 * TinyCBOR's but deterministic encoding, so cbor_value_validate() runs only
 * for deterministic = TRUE. Three checks TinyCBOR offers are the walk's:
 *  - UTF-8, not CborValidateUtf8: in the same pass, and with an offset;
 *  - trailing bytes, not CborValidateCompleteData: in a sequence the next
 *    item's bytes are not garbage, and for a prefix they are not read;
 *  - tag content, not CborValidateTagUse: TinyCBOR 7.0's table allows only
 *    an integer under tag 1, where RFC 8949 section 3.4.2 also allows a
 *    float, so it refuses Appendix A's 1(1363896240.5). See tag_content_ok(). */
#define ZU_VALIDATE_FLAGS (CborValidateCanonicalFormat)

#define ZU_INTERRUPT_EVERY 65536u

/* Map keys are compared by value (design section 6.5). Keys of different
 * kinds are never equal: the integer 1 and the float 1.0 are different CBOR
 * values. */
enum { KEY_INT, KEY_FLOAT, KEY_SIMPLE, KEY_BYTES, KEY_TEXT, KEY_ENCODED };

/* A frame's part in an RFC 8746 multi-dimensional array (tags 40, 1040):
 * the tag's content [dimensions, elements], the dimensions array, or a
 * plain elements array. */
enum { ND_NONE, ND_OUTER, ND_DIMS, ND_ELEMS };

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
    uint8_t nd_role;            /* ND_*: its part in a multi-dimensional array */
    uint8_t nd_dims_ok, nd_elems_ok;    /* ND_OUTER: both parts seen */
    uint64_t nd_product;        /* ND_OUTER: product of the dimensions, saturating */
    uint64_t nd_elems;          /* ND_OUTER: the number of elements */
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
    zu_key *sort_tmp;       /* merge-sort buffer, reused across maps */
    size_t sort_cap;
} zu_walker;

/* ---- faults ---------------------------------------------------------------- */

static double offset_of(const zu_walker *w, const uint8_t *at)
{
    return at ? (double)(at - w->buf) : ZU_NO_OFFSET;
}

static int fail(zu_walker *w, const char *status, const char *detail,
                const uint8_t *at)
{
    w->fault->status = status;
    w->fault->detail = detail;
    w->fault->offset = offset_of(w, at);
    w->fault->limit = NULL;
    w->fault->limit_value = ZU_NO_OFFSET;
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
    void *p = zu_scratch(newcap, size);
    if (used)
        memcpy(p, old, used * size);
    *cap = newcap;
    return p;
}

static int count_item(zu_walker *w, const uint8_t *at)
{
    w->items++;
    if (w->items > w->opt->max_items)  /* GUARD: items */
        return fail_limit(w, ZU_ERR_ITEM_LIMIT, "max_items",
                          (double)w->opt->max_items, at);
    if (w->items % ZU_INTERRUPT_EVERY == 0)
        zu_interrupt_check();
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
 * quadratic on an adversarial order, and the keys are the adversary's.
 * Small maps, the common case, take an insertion sort in place; larger ones
 * share one buffer, grown as needed, rather than allocating per map. */
static void sort_keys(zu_walker *w, zu_key *a, size_t n)
{
    if (n <= 16) {
        for (size_t i = 1; i < n; i++) {
            zu_key k = a[i];
            size_t j = i;
            while (j > 0 && key_cmp(&k, &a[j - 1]) < 0) {
                a[j] = a[j - 1];
                j--;
            }
            a[j] = k;
        }
        return;
    }
    if (n > w->sort_cap) {
        w->sort_cap = n < 2 * w->sort_cap ? 2 * w->sort_cap : n;
        w->sort_tmp = (zu_key *) zu_scratch(w->sort_cap, sizeof(zu_key));
    }
    zu_key *tmp = w->sort_tmp;
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
    sort_keys(w, k, n);
    for (size_t i = 1; i < n; i++) {
        if (key_cmp(&k[i - 1], &k[i]) == 0) {  /* GUARD: duplicate-keys */
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

/* ---- multi-dimensional arrays ------------------------------------------------- */

static zu_frame *parent_frame(zu_walker *w)
{
    return w->sp ? &w->frames[w->sp - 1] : NULL;
}

/* The shape rules of RFC 8746 section 3.1, for an element about to be
 * walked whose parent takes part in a multi-dimensional array. The content
 * of tag 40 or 1040 is exactly [dimensions, elements]: the dimensions an
 * untagged, non-empty array of unsigned integers; the elements an untagged
 * array, or one typed array (Stage 12). The product of the dimensions must
 * be the number of elements, which close_container() checks. Returns
 * nonzero on a fault. */
static int nd_element(zu_walker *w, const CborValue *it, int tags, CborTag tag,
                      CborType type, const uint8_t *start)
{
    zu_frame *p = parent_frame(w);
    if (!p || p->nd_role == ND_NONE || p->nd_role == ND_ELEMS)
        return 0;
    int ok;
    if (p->nd_role == ND_DIMS)
        ok = tags == 0 && type == CborIntegerType && !cbor_value_is_negative_integer(it);
    else if (p->count == 0)
        ok = tags == 0 && type == CborArrayType;
    else if (p->count == 1)
        ok = (tags == 0 && type == CborArrayType) ||
             (tags == 1 && zu_typed_size(tag) && type == CborByteStringType);
    else
        ok = 0;
    if (!ok)  /* GUARD: array-parts */
        return fail(w, ZU_ERR_ARRAY_SHAPE, "a multi-dimensional array is not "
                    "[dimensions, elements] of the kinds RFC 8746 allows", start);
    return 0;
}

/* A dimension, multiplied into the product its array's parent keeps. */
static void nd_dimension(zu_walker *w, uint64_t d)
{
    zu_frame *outer = &w->frames[w->sp - 2];
    if (d && outer->nd_product > UINT64_MAX / d)
        outer->nd_product = UINT64_MAX;     /* never equals a real count */
    else
        outer->nd_product *= d;
}

static int open_container(zu_walker *w, CborValue *it, const uint8_t *start, int tags,
                          CborTag tag)
{
    int is_map = cbor_value_is_map(it);
    if (w->depth + 1 > w->opt->max_depth)  /* GUARD: depth-containers */
        return fail_limit(w, ZU_ERR_DEPTH_LIMIT, "max_depth", w->opt->max_depth, start);

    /* Every element costs at least one byte, so a length the rest of the
     * input cannot hold is truncation, found here before TinyCBOR is asked to
     * track it (it refuses lengths of 2^32 and over as "too large"). */
    if (cbor_value_is_length_known(it)) {
        size_t n, avail = (size_t)(w->end - start);
        CborError err = is_map ? cbor_value_get_map_length(it, &n)
                               : cbor_value_get_array_length(it, &n);
        if (err || n > avail / (is_map ? 2 : 1))  /* GUARD: length-headers */
            return fail_cbor(w, CborErrorUnexpectedEOF, start);
    }

    zu_frame *f = &w->frames[w->sp];
    memset(f, 0, sizeof *f);
    f->type = (uint8_t) cbor_value_get_type(it);
    f->tag_levels = tags;
    f->key_base = w->n_keys;
    zu_frame *p = parent_frame(w);
    if (tags && (tag == 40 || tag == 1040)) {
        f->nd_role = ND_OUTER;
        f->nd_product = 1;
    } else if (p && p->nd_role == ND_OUTER) {
        f->nd_role = p->count == 0 ? ND_DIMS : ND_ELEMS;
    }
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
        if (f->count % 2)  /* GUARD: odd-map */
            return fail(w, ZU_ERR_ODD_MAP, NULL, cbor_value_get_next_byte(&f->it));
        if (!w->opt->duplicate_keys) {
            if (check_duplicates(w, f->key_base))
                return 1;
            w->n_keys = f->key_base;
        }
    }
    if (f->nd_role != ND_NONE) {
        zu_frame *p = w->sp > 1 ? &w->frames[w->sp - 2] : NULL;
        if (f->nd_role == ND_DIMS) {
            if (f->count == 0)
                return fail(w, ZU_ERR_ARRAY_SHAPE, "a multi-dimensional array has no dimensions",
                            cbor_value_get_next_byte(&f->it));
            p->nd_dims_ok = 1;
        } else if (f->nd_role == ND_ELEMS) {
            p->nd_elems = f->count;
            p->nd_elems_ok = 1;
        } else {
            int shape_ok = f->count == 2 && f->nd_dims_ok && f->nd_elems_ok
                           && f->nd_product == f->nd_elems;
            if (!shape_ok)  /* GUARD: array-shape */
                return fail(w, ZU_ERR_ARRAY_SHAPE, "the dimensions of a multi-dimensional "
                            "array do not multiply to its number of elements",
                            cbor_value_get_next_byte(&f->it));
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
        /* UTF-8 here rather than in cbor_value_validate(): one pass instead
         * of two, and the fault gets an offset. Each chunk must be valid on
         * its own (RFC 8949 section 3.2.3). */
        if (text && !zu_utf8_valid((const uint8_t *)p, n))  /* GUARD: utf8 */
            return fail_cbor(w, CborErrorInvalidUtf8TextString, (const uint8_t *)p);
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
        uint8_t *joined = (uint8_t *) zu_scratch(*total ? *total : 1, 1);
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

/* An item's kind for the tag-content table (zu_tag_content_ok() in
 * zu_check.h, which the encoder applies too). */
static int kind_of(CborType type)
{
    switch (type) {
    case CborIntegerType: return ZU_KIND_INT;
    case CborByteStringType: return ZU_KIND_BYTES;
    case CborTextStringType: return ZU_KIND_TEXT;
    case CborArrayType: return ZU_KIND_ARRAY;
    case CborMapType: return ZU_KIND_MAP;
    case CborTagType: return ZU_KIND_TAG;
    case CborHalfFloatType: case CborFloatType: case CborDoubleType: return ZU_KIND_FLOAT;
    default: return ZU_KIND_OTHER;
    }
}

/* RFC 8949 section 3.4.3: in preferred serialization a bignum has no leading
 * zero byte, and one that fits a plain integer is not a bignum at all. */
static int check_bignum(zu_walker *w, const uint8_t *content, size_t n,
                        const uint8_t *start)
{
    if (n == 0 || content[0] == 0 || n <= 8)  /* GUARD: bignum-preferred */
        return fail(w, ZU_ERR_BIGNUM_NOT_PREFERRED, NULL, start);
    return 0;
}

static int walk_element(zu_walker *w, CborValue *it)
{
    const uint8_t *start = cbor_value_get_next_byte(it);
    int key = at_key(w);
    int tags = 0;
    CborTag tag = 0;
    const uint8_t *tag_at = NULL;   /* the innermost tag */
    CborError err;

    if (w->sp)
        w->frames[w->sp - 1].elem_start = start;

    while (cbor_value_is_tag(it)) {
        if (count_item(w, cbor_value_get_next_byte(it)))
            return 1;
        if (w->depth + 1 > w->opt->max_depth)  /* GUARD: depth-tags */
            return fail_limit(w, ZU_ERR_DEPTH_LIMIT, "max_depth", w->opt->max_depth,
                              cbor_value_get_next_byte(it));
        w->depth++;
        tags++;
        tag_at = cbor_value_get_next_byte(it);
        cbor_value_get_tag(it, &tag);
        err = cbor_value_advance_fixed(it);
        if (err)
            return fail_cbor(w, err, cbor_value_get_next_byte(it));
        if (!zu_tag_content_ok(tag, kind_of(cbor_value_get_type(it))))  /* GUARD: tag-content */
            return fail_cbor(w, CborErrorInappropriateTagForType, tag_at);
    }
    if (count_item(w, cbor_value_get_next_byte(it)))
        return 1;

    CborType type = cbor_value_get_type(it);
    if (nd_element(w, it, tags, tag, type, start))
        return 1;
    if (type == CborArrayType || type == CborMapType)
        return open_container(w, it, start, tags, tag);

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
        /* RFC 8949 section 3.4.1 and RFC 8943: date text that does not
         * parse is invalid, so the check refuses it whatever the decoder's
         * tags and handlers would do with it (design section 6.7). */
        int date = tags && (tag == 0 || tag == 1004) && type == CborTextStringType;
        if (walk_string(w, it, k != NULL || bignum || date, &content, &total))
            return 1;
        if (bignum && check_bignum(w, content, total, start))
            return 1;
        if (date && !zu_date_text_ok(tag, (const char *) content, total))  /* GUARD: date-content */
            return fail(w, ZU_ERR_INVALID_DATE, tag == 0
                        ? "tag 0 content is not an RFC 3339 date/time"
                        : "tag 1004 content is not an RFC 3339 full-date", tag_at);
        int size = tags && type == CborByteStringType ? zu_typed_size(tag) : 0;
        if (size) {
            if (total % (size_t) size)  /* GUARD: typed-array-length */
                return fail(w, ZU_ERR_TYPED_ARRAY, "a typed array's length is not "
                            "a whole number of elements", start);
            zu_frame *p = parent_frame(w);
            if (p && p->nd_role == ND_OUTER) {
                p->nd_elems = total / (size_t) size;
                p->nd_elems_ok = 1;
            }
        }
        if (k) {
            k->kind = type == CborTextStringType ? KEY_TEXT : KEY_BYTES;
            k->ptr = content;
            k->len = total;
        }
        break;
    }
    case CborIntegerType:
        if (w->sp && w->frames[w->sp - 1].nd_role == ND_DIMS) {
            uint64_t d;
            cbor_value_get_raw_integer(it, &d);
            nd_dimension(w, d);
        }
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

/* A fault in the item at pos. A stream stops before the item without one
 * when the input ends inside it, since more input may complete it -- every
 * item's head and content are read through TinyCBOR, which reports running
 * out of input as CborErrorUnexpectedEOF, and the walk reports a length the
 * rest cannot hold the same way -- or when items before it are delivered
 * first; the next read starts at it and reports its fault. */
static int stream_stop(zu_walker *w, size_t pos)
{
    if (!w->opt->stream)
        return 1;
    if (strcmp(w->fault->status, "CborErrorUnexpectedEOF") != 0
        && (!w->plan || w->plan->n_items == 0))
        return 1;
    w->fault->status = NULL;
    if (w->plan)
        w->plan->consumed = pos;
    return 0;
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
    w.frames = (zu_frame *) zu_scratch((size_t)opt->max_depth + 1, sizeof(zu_frame));
    fault->status = NULL;
    if (plan) {
        plan->counts = NULL;
        plan->n = plan->cap = 0;
        plan->n_items = 0;
        plan->consumed = 0;
    }

    if (len == 0) {
        if (opt->sequence)
            return 0;
        return fail_cbor(&w, CborErrorUnexpectedEOF, buf);
    }


    size_t pos = 0;
    while (pos < len) {
        CborParser parser;
        CborValue it;
        if (opt->stream)
            w.items = 0;        /* max_items is per item */
        CborError err = cbor_parser_init(buf + pos, len - pos, 0, &parser, &it);
        if (err)
            fail_cbor(&w, err, buf + pos);
        CborValue start = it;
        /* Deterministic encoding is the one check left to TinyCBOR, and
         * it reports no position (design section 10). */
        if (!err && !walk_item(&w, &it) && opt->deterministic) {
            err = cbor_value_validate(&start, ZU_VALIDATE_FLAGS);
            if (err)
                fail_cbor(&w, err, NULL);
        }
        if (fault->status)
            return stream_stop(&w, pos);
        pos = (size_t)(cbor_value_get_next_byte(&it) - buf);
        if (plan) {
            plan->n_items++;
            plan->consumed = pos;
        }
        /* A prefix stops here: whatever follows is the caller's framing,
         * and TinyCBOR has not read it (at the top level it preparses
         * nothing past the item). */
        if (opt->prefix)
            return 0;
        if (!opt->sequence && pos < len)  /* GUARD: trailing-bytes */
            return fail_cbor(&w, CborErrorGarbageAtEnd, buf + pos);
    }
    return 0;
}
