#ifndef ZU_CBOR_H
#define ZU_CBOR_H

/* Internal prototypes that take TinyCBOR types. */

#include "zucbor.h"
#include "cbor.h"

const char *zu_diagnose_item(const CborValue *it, size_t *len);

#endif
