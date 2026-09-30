/* Compile-time checks against TinyCBOR internals that its public header does
 * not expose. Included in the same order TinyCBOR's own sources use, and with
 * no R headers, so nothing here can disagree with how TinyCBOR is built. */
#include "cborinternalmacros_p.h"
#include "cbor.h"
#include "cborinternal_p.h"
#include "zu_config.h"

#if CBOR_PARSER_MAX_RECURSIONS - 1 != ZU_MAX_DEPTH_CAP
#error "ZU_MAX_DEPTH_CAP must be one less than CBOR_PARSER_MAX_RECURSIONS"
#endif

/* ISO C forbids an empty translation unit. */
typedef int zu_tinycbor_check_unit;
