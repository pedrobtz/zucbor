#ifndef ZUCBOR_H
#define ZUCBOR_H

#include <stddef.h>
#include <stdint.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "zu_config.h"

/* ---- check phase (zu_walk.c), design sections 4 and 11 -------------------
 * Nothing here allocates an R object: scratch is R_alloc()ed, which R frees
 * when the .Call returns or unwinds (design section 12). */

typedef struct {
    int max_depth;          /* 1 .. ZU_MAX_DEPTH_CAP */
    uint64_t max_items;     /* UINT64_MAX for Inf */
    int duplicate_keys;     /* nonzero: accept them */
    int deterministic;      /* nonzero: RFC 8949 section 4.2.1 input only */
    int sequence;           /* nonzero: zero or more items (RFC 8742) */
} zu_check_opts;

/* Why a check failed. status is an enumerator name (a CborError, or one of
 * zucbor's ZU_ERR_* below); R maps it to a condition class by name. */
typedef struct {
    const char *status;     /* NULL: no fault */
    const char *detail;     /* TinyCBOR's wording, or NULL */
    double offset;          /* 0-based byte offset, NA_REAL when unknown */
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

/* ---- zu_cond.c ------------------------------------------------------------ */

/* The enumerator name of a CborError, or NULL for a value no enumerator has. */
const char *zu_cbor_status_name(int err);
SEXP zu_fault_sexp(const zu_fault *fault);

/* ---- zu_float.c ----------------------------------------------------------- */

double zu_half_to_double(uint16_t half);
void zu_format_double(double d, char *buf);   /* zu_diag.c; buf >= 40 bytes */
int zu_double_to_half(double d, uint16_t *out);
int zu_utf8_valid(const uint8_t *s, size_t n);

/* ---- zu_bigint.c, zu_time.c ---------------------------------------------- */

size_t zu_u64_to_dec(uint64_t v, char *buf);
const char *zu_magnitude_to_dec(const uint8_t *mag, size_t n, int add_one, int negative);
int zu_parse_rfc3339(const char *s, size_t len, double *secs);
int zu_parse_full_date(const char *s, size_t len, double *days);
int zu_format_full_date(double days, char *buf);
const uint8_t *zu_dec_to_magnitude(const char *dec, size_t *n);

/* ---- .Call entry points, registered in init.c ----------------------------- */

SEXP zucbor_build_info(void);
SEXP zucbor_status_names(void);
SEXP zucbor_check(SEXP x, SEXP sequence, SEXP deterministic,
                  SEXP duplicate_keys, SEXP max_depth, SEXP max_items);
SEXP zucbor_decode(SEXP x, SEXP opts, SEXP max_items, SEXP call);
SEXP zucbor_encode(SEXP x, SEXP opts, SEXP call);
SEXP zucbor_half_roundtrip(void);
SEXP zucbor_diagnose(SEXP x, SEXP opts, SEXP max_items);
SEXP zucbor_format_roundtrip(SEXP x);

#endif
