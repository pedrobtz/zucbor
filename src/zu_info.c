#include <stdio.h>

#include "zucbor.h"
#include "cbor.h"

/* RFC 8949 Appendix A: {"a": 1, "b": [2, 3]}. Validating it proves the
 * vendored parser and validator are linked and working, without any of the
 * package's own decoding code. */
static const uint8_t smoke_item[] = {
    0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03
};

static int smoke_validates(void)
{
    CborParser parser;
    CborValue it;
    if (cbor_parser_init(smoke_item, sizeof smoke_item, 0, &parser, &it) != CborNoError)
        return 0;
    return cbor_value_validate(&it, CborValidateUtf8 | CborValidateTagUse |
                                    CborValidateCompleteData) == CborNoError;
}

SEXP zucbor_build_info(void)
{
    char version[32];
    snprintf(version, sizeof version, "%d.%d.%d", TINYCBOR_VERSION_MAJOR,
             TINYCBOR_VERSION_MINOR, TINYCBOR_VERSION_PATCH);

    const char *names[] = {"tinycbor_version", "max_depth_cap", "smoke_ok", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_mkString(version));
    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ZU_MAX_DEPTH_CAP));
    SET_VECTOR_ELT(out, 2, Rf_ScalarLogical(smoke_validates()));
    UNPROTECT(1);
    return out;
}
