#include "zucbor.h"

/* Every status a fault can carry, for the test that R's class map is
 * complete (zu_status.c). */
SEXP zucbor_status_names(void)
{
    size_t n = zu_status_count();
    SEXP out = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) n));
    for (size_t i = 0; i < n; i++)
        SET_STRING_ELT(out, (R_xlen_t) i, Rf_mkChar(zu_status_at(i)));
    UNPROTECT(1);
    return out;
}

/* A fault as the list R's zu_raise_fault() takes. */
SEXP zu_fault_sexp(const zu_fault *fault)
{
    const char *names[] = {"status", "detail", "offset", "limit", "limit_value", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_mkString(fault->status));
    SET_VECTOR_ELT(out, 1, fault->detail ? Rf_mkString(fault->detail)
                                         : Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 2, Rf_ScalarReal(fault->offset));
    SET_VECTOR_ELT(out, 3, fault->limit ? Rf_mkString(fault->limit)
                                        : Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 4, Rf_ScalarReal(fault->limit ? fault->limit_value : NA_REAL));
    Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("zu_fault"));
    UNPROTECT(1);
    return out;
}
