#ifndef ZUCBOR_H
#define ZUCBOR_H

#include <stddef.h>
#include <stdint.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "zu_check.h"

/* ---- zu_cond.c ------------------------------------------------------------ */

SEXP zu_fault_sexp(const zu_fault *fault);

/* ---- zu_diag.c ------------------------------------------------------------ */

void zu_format_double(double d, char *buf);   /* buf >= 40 bytes */

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
SEXP zucbor_decode(SEXP x, SEXP opts, SEXP max_items, SEXP call, SEXP handlers);
SEXP zucbor_encode(SEXP x, SEXP opts, SEXP call, SEXP ns);
SEXP zucbor_half_roundtrip(void);
SEXP zucbor_diagnose(SEXP x, SEXP opts, SEXP max_items);
SEXP zucbor_annotate(SEXP x, SEXP opts, SEXP max_items);
SEXP zucbor_format_roundtrip(SEXP x);

#endif
