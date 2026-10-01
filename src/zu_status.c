/* Status names, without R: the check phase reports them, R maps them to
 * condition classes by name (design section 10). */
#include "zu_check.h"
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
    ZU_ERR_NUL_IN_TEXT,
    ZU_ERR_STRING_TOO_LONG,
    ZU_ERR_BIG_INTEGER,
    ZU_ERR_TAG_TOO_LARGE,
    ZU_ERR_INVALID_DATE,
    ZU_ERR_KEY_COLLISION,
    ZU_ERR_UNSUPPORTED_TYPE,
    ZU_ERR_INVALID_VALUE,
    ZU_ERR_TYPED_ARRAY,
    ZU_ERR_ARRAY_SHAPE,
    ZU_ERR_DIMENSION,
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
size_t zu_status_count(void)
{
    return N_CBOR_STATUSES - 1 + N_OWN_STATUSES;
}

const char *zu_status_at(size_t i)
{
    for (size_t k = 0; k < N_CBOR_STATUSES; k++) {
        if (cbor_statuses[k].code == CborNoError)
            continue;
        if (i-- == 0)
            return cbor_statuses[k].name;
    }
    return i < N_OWN_STATUSES ? own_statuses[i] : NULL;
}
