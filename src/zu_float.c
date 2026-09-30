#include <math.h>
#include <stdio.h>
#include <string.h>

#include "zucbor.h"

/* IEEE 754 binary16 to double, exactly: RFC 8949 Appendix D. Project code
 * rather than TinyCBOR's decode_half(), which is private to its translation
 * units and picks compiler intrinsics by platform (design section 8). */
double zu_half_to_double(uint16_t half)
{
    int exp = (half >> 10) & 0x1f;
    int mant = half & 0x3ff;
    double val;
    if (exp == 0)
        val = ldexp(mant, -24);
    else if (exp != 31)
        val = ldexp(mant + 1024, exp - 25);
    else
        val = mant == 0 ? INFINITY : NAN;
    return (half & 0x8000) ? -val : val;
}

/* The shortest decimal that reads back as d, in diagnostic-notation style:
 * always a decimal point or exponent, so 1.0 is not mistaken for the
 * integer 1; NaN and Infinity spelled as RFC 8949 section 8 does. For naming
 * float map keys under map_keys = "string", where TinyCBOR's printer would
 * append its width suffix ("1.5f16"). R keeps LC_NUMERIC at "C", so '.' is
 * the decimal point. buf must hold at least 32 bytes. */
void zu_format_double(double d, char *buf)
{
    if (isnan(d)) {
        strcpy(buf, "NaN");
        return;
    }
    if (isinf(d)) {
        strcpy(buf, d > 0 ? "Infinity" : "-Infinity");
        return;
    }
    for (int prec = 1; prec <= 17; prec++) {
        snprintf(buf, 32, "%.*g", prec, d);
        if (R_strtod(buf, NULL) == d)
            break;
    }
    if (!strpbrk(buf, ".e"))
        strcat(buf, ".0");
}
