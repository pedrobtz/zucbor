/* cbor_validate()'s entry point: the check phase alone (zu_walk.c). */
#include "zucbor.h"

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
