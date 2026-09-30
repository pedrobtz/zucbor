#include "zucbor.h"
#include "cbor.h"

/* Every CborError enumerator in the vendored cbor.h, by name. R maps a fault
 * to a condition class by this name, never by TinyCBOR's English, so
 * rewording upstream cannot change which handler catches an error.
 * tools/check-status-table fails if cbor.h gains an enumerator missing here,
 * and test-conditions.R fails if R's class map misses one. */
#define ZU_STATUS(x) {x, #x}
static const struct {
    int code;
    const char *name;
} cbor_statuses[] = {
    ZU_STATUS(CborNoError),
    ZU_STATUS(CborUnknownError),
    ZU_STATUS(CborErrorUnknownLength),
    ZU_STATUS(CborErrorAdvancePastEOF),
    ZU_STATUS(CborErrorIO),
    ZU_STATUS(CborErrorGarbageAtEnd),
    ZU_STATUS(CborErrorUnexpectedEOF),
    ZU_STATUS(CborErrorUnexpectedBreak),
    ZU_STATUS(CborErrorUnknownType),
    ZU_STATUS(CborErrorIllegalType),
    ZU_STATUS(CborErrorIllegalNumber),
    ZU_STATUS(CborErrorIllegalSimpleType),
    ZU_STATUS(CborErrorNoMoreStringChunks),
    ZU_STATUS(CborErrorUnknownSimpleType),
    ZU_STATUS(CborErrorUnknownTag),
    ZU_STATUS(CborErrorInappropriateTagForType),
    ZU_STATUS(CborErrorDuplicateObjectKeys),
    ZU_STATUS(CborErrorInvalidUtf8TextString),
    ZU_STATUS(CborErrorExcludedType),
    ZU_STATUS(CborErrorExcludedValue),
    ZU_STATUS(CborErrorImproperValue),
    ZU_STATUS(CborErrorOverlongEncoding),
    ZU_STATUS(CborErrorMapKeyNotString),
    ZU_STATUS(CborErrorMapNotSorted),
    ZU_STATUS(CborErrorMapKeysNotUnique),
    ZU_STATUS(CborErrorTooManyItems),
    ZU_STATUS(CborErrorTooFewItems),
    ZU_STATUS(CborErrorDataTooLarge),
    ZU_STATUS(CborErrorNestingTooDeep),
    ZU_STATUS(CborErrorUnsupportedType),
    ZU_STATUS(CborErrorUnimplementedValidation),
    ZU_STATUS(CborErrorJsonObjectKeyIsAggregate),
    ZU_STATUS(CborErrorJsonObjectKeyNotString),
    ZU_STATUS(CborErrorJsonNotImplemented),
    ZU_STATUS(CborErrorOutOfMemory),
    ZU_STATUS(CborErrorInternalError),
};
#undef ZU_STATUS

#define N_CBOR_STATUSES (sizeof cbor_statuses / sizeof cbor_statuses[0])

static const char *const own_statuses[] = {
    ZU_ERR_DEPTH_LIMIT,
    ZU_ERR_ITEM_LIMIT,
    ZU_ERR_DUPLICATE_KEY,
    ZU_ERR_BIGNUM_NOT_PREFERRED,
    ZU_ERR_ODD_MAP,
};

#define N_OWN_STATUSES (sizeof own_statuses / sizeof own_statuses[0])

const char *zu_cbor_status_name(int err)
{
    for (size_t i = 0; i < N_CBOR_STATUSES; i++)
        if (cbor_statuses[i].code == err)
            return cbor_statuses[i].name;
    return NULL;
}

/* Every status a fault can carry, for the test that R's class map is
 * complete. CborNoError is not a fault and is left out. */
SEXP zucbor_status_names(void)
{
    SEXP out = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)(N_CBOR_STATUSES - 1 + N_OWN_STATUSES)));
    R_xlen_t k = 0;
    for (size_t i = 0; i < N_CBOR_STATUSES; i++)
        if (cbor_statuses[i].code != CborNoError)
            SET_STRING_ELT(out, k++, Rf_mkChar(cbor_statuses[i].name));
    for (size_t i = 0; i < N_OWN_STATUSES; i++)
        SET_STRING_ELT(out, k++, Rf_mkChar(own_statuses[i]));
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
