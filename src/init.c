#include <R_ext/Rdynload.h>

#include "zucbor.h"

static const R_CallMethodDef CallEntries[] = {
    {"zucbor_build_info", (DL_FUNC) &zucbor_build_info, 0},
    {NULL, NULL, 0}
};

void R_init_zucbor(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
