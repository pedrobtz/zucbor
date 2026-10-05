#ifndef ZU_CHECK_H
#define ZU_CHECK_H

/* The check phase's interface (design sections 4 and 11), with no SEXP in
 * sight, so it builds without R for fuzzing (roadmap Stage 7): compile with
 * -DZU_STANDALONE and link a harness that provides zu_scratch(). */

#include <stddef.h>
#include <stdint.h>

#include "zu_config.h"

/* Scratch memory, released as a whole: R_alloc() in the package, which R
 * frees when the .Call returns or unwinds (design section 12); an arena the
 * harness resets after each input in the standalone build. */
#ifdef ZU_STANDALONE
#include <math.h>
void *zu_scratch(size_t n, size_t size);
#define zu_interrupt_check() ((void) 0)
#define ZU_NO_OFFSET NAN
#else
#include <R_ext/Arith.h>
#include <R_ext/Memory.h>
#include <R_ext/Utils.h>
#define zu_scratch(n, size) ((void *) R_alloc((n), (int) (size)))
#define zu_interrupt_check() R_CheckUserInterrupt()
#define ZU_NO_OFFSET NA_REAL
#endif

typedef struct {
    int max_depth;          /* 1 .. ZU_MAX_DEPTH_CAP */
    uint64_t max_items;     /* UINT64_MAX for Inf */
    int duplicate_keys;     /* nonzero: accept them */
    int deterministic;      /* nonzero: RFC 8949 section 4.2.1 input only */
    int sequence;           /* nonzero: zero or more items (RFC 8742) */
    int prefix;             /* nonzero: the first item only; what follows is
                             * not read (cbor_decode_prefix()). Not with
                             * sequence. */
    int stream;             /* nonzero: a sequence read from a stream
                             * (cbor_read_seq(each =)). The check stops at
                             * the first item that is not complete and good:
                             * one the input ends inside is left for the
                             * next read, unreported, and a faulty one is
                             * reported only if it comes first, so the items
                             * before it are delivered. max_items is per
                             * item. Only with sequence. */
} zu_check_opts;

/* Why a check failed. status is an enumerator name (a CborError, or one of
 * zucbor's ZU_ERR_* below); R maps it to a condition class by name. */
typedef struct {
    const char *status;     /* NULL: no fault */
    const char *detail;     /* TinyCBOR's wording, or NULL */
    double offset;          /* 0-based byte offset, ZU_NO_OFFSET when unknown */
    const char *limit;      /* the limit argument's name, or NULL */
    double limit_value;
} zu_fault;

/* What the build phase needs from the check phase: the element count of
 * every container, in the order the walk met them (preorder). Maps count
 * pairs. Indefinite-length containers are why this exists; for the rest it
 * saves re-reading a header the check has already proved. */
typedef struct {
    size_t *counts;
    size_t n, cap;
    size_t n_items;         /* top-level items found */
    size_t consumed;        /* bytes the items used; under stream, where
                             * the first item not delivered starts */
} zu_plan;

/* Runs the whole check phase over buf. Returns 0 and fills plan (which may
 * be NULL), or returns 1 and fills fault. Never raises. */
int zu_check(const uint8_t *buf, size_t len, const zu_check_opts *opt,
             zu_plan *plan, zu_fault *fault);

/* zucbor's own statuses, alongside TinyCBOR's CborError names. */
#define ZU_ERR_DEPTH_LIMIT          "ZU_ERR_DEPTH_LIMIT"
#define ZU_ERR_ITEM_LIMIT           "ZU_ERR_ITEM_LIMIT"
#define ZU_ERR_DUPLICATE_KEY        "ZU_ERR_DUPLICATE_KEY"
#define ZU_ERR_BIGNUM_NOT_PREFERRED "ZU_ERR_BIGNUM_NOT_PREFERRED"
#define ZU_ERR_ODD_MAP              "ZU_ERR_ODD_MAP"
#define ZU_ERR_NUL_IN_TEXT          "ZU_ERR_NUL_IN_TEXT"
#define ZU_ERR_STRING_TOO_LONG      "ZU_ERR_STRING_TOO_LONG"
#define ZU_ERR_BIG_INTEGER          "ZU_ERR_BIG_INTEGER"
#define ZU_ERR_TAG_TOO_LARGE        "ZU_ERR_TAG_TOO_LARGE"
#define ZU_ERR_INVALID_DATE         "ZU_ERR_INVALID_DATE"
#define ZU_ERR_KEY_COLLISION        "ZU_ERR_KEY_COLLISION"
#define ZU_ERR_UNSUPPORTED_TYPE     "ZU_ERR_UNSUPPORTED_TYPE"
#define ZU_ERR_INVALID_VALUE        "ZU_ERR_INVALID_VALUE"
#define ZU_ERR_TYPED_ARRAY          "ZU_ERR_TYPED_ARRAY"
#define ZU_ERR_ARRAY_SHAPE          "ZU_ERR_ARRAY_SHAPE"
#define ZU_ERR_DIMENSION            "ZU_ERR_DIMENSION"
#define ZU_ERR_CELL_LIMIT           "ZU_ERR_CELL_LIMIT"

/* The element size in bytes of an RFC 8746 typed array tag (64-87, but not
 * the reserved 76), or 0 for any other tag. Bits 0b010fsell: f float, s
 * signed, e little-endian, ll the size, 8 << ll bits for an integer and
 * 16 << ll for a float. */
static inline int zu_typed_size(uint64_t tag)
{
    if (tag < 64 || tag > 87 || tag == 76)
        return 0;
    return (tag & 16) ? 2 << (tag & 3) : 1 << (tag & 3);
}

/* The kind of an item, as far as the tag-content table cares: the walk
 * derives it from TinyCBOR's type, the encoder from the initial byte it
 * wrote, so both apply one table (design sections 8 and 11). */
enum {
    ZU_KIND_INT, ZU_KIND_BYTES, ZU_KIND_TEXT, ZU_KIND_ARRAY, ZU_KIND_MAP,
    ZU_KIND_TAG, ZU_KIND_FLOAT, ZU_KIND_OTHER
};

/* The content kinds RFC 8949 and RFC 8943 require under the tags that
 * restrict them: TinyCBOR's knownTagData with two corrections -- tag 1 also
 * takes a float, and 21-23 take any item -- plus 100 and 1004, which zucbor
 * converts. A tag not listed may wrap anything. */
static inline int zu_tag_content_ok(uint64_t tag, int kind)
{
    switch (tag) {
    case 0: case 32: case 33: case 34: case 35: case 36: case 1004:
        return kind == ZU_KIND_TEXT;
    case 1:
        return kind == ZU_KIND_INT || kind == ZU_KIND_FLOAT;
    case 2: case 3: case 24:
        return kind == ZU_KIND_BYTES;
    case 4: case 5: case 16: case 17: case 18: case 96: case 97: case 98:
    case 40: case 1040:
        return kind == ZU_KIND_ARRAY;
    case 100:
        return kind == ZU_KIND_INT;
    default:
        /* RFC 8746 typed arrays: a byte string. */
        return !zu_typed_size(tag) || kind == ZU_KIND_BYTES;
    }
}

/* zu_status.c: the enumerator name of a CborError, or NULL for a value no
 * enumerator has; and every status a fault can carry, for R's class map. */
const char *zu_cbor_status_name(int err);
size_t zu_status_count(void);
const char *zu_status_at(size_t i);

/* zu_float.c */
double zu_half_to_double(uint16_t half);
int zu_double_to_half(double d, uint16_t *out);
int zu_utf8_valid(const uint8_t *s, size_t n);

/* zu_time.c: no R API either, so the check phase can validate the text
 * of tags 0 and 1004 (design section 6.7). Each returns 0 on success. */
int zu_parse_rfc3339(const char *s, size_t len, double *secs);
int zu_parse_full_date(const char *s, size_t len, double *days);
int zu_format_full_date(double days, char *buf);
/* Nonzero if s is valid content for tag 0 (an RFC 3339 date/time) or tag
 * 1004 (an RFC 3339 full-date). */
int zu_date_text_ok(uint64_t tag, const char *s, size_t len);

#endif
