#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zu_check.h"

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

/* d as IEEE 754 binary16, when that is exact: 0 otherwise. NaN is the
 * caller's (it always writes the canonical 0x7e00). Design section 8:
 * width selection is project code, tested over all 65,536 patterns. */
int zu_double_to_half(double d, uint16_t *out)
{
    uint16_t sign = signbit(d) ? 0x8000 : 0;
    double a = fabs(d);
    if (a == 0) {
        *out = sign;
        return 1;
    }
    if (isinf(a)) {
        *out = (uint16_t)(sign | 0x7c00);
        return 1;
    }
    if (isnan(a) || a > 65504.0)
        return 0;
    int e;
    frexp(a, &e);                   /* a = 1.f * 2^(e - 1) */
    int E = e - 1;
    if (E >= -14) {                 /* normal: 10 fraction bits */
        double scaled = ldexp(a, 10 - E);
        if (scaled != floor(scaled))
            return 0;
        *out = (uint16_t)(sign | ((E + 15) << 10) | ((int) scaled - 1024));
        return 1;
    }
    double scaled = ldexp(a, 24);   /* subnormal: units of 2^-24 */
    if (scaled != floor(scaled) || scaled >= 1024)
        return 0;
    *out = (uint16_t)(sign | (int) scaled);
    return 1;
}

/* RFC 3629 UTF-8: no overlong forms, no surrogates, nothing past U+10FFFF. */
int zu_utf8_valid(const uint8_t *s, size_t n)
{
    size_t i = 0;
    while (i < n) {
        uint8_t c = s[i];
        if (c < 0x80) {
            i++;
            continue;
        }
        size_t len;
        uint32_t cp, min;
        if (c >= 0xc2 && c <= 0xdf) {
            len = 2; cp = c & 0x1f; min = 0x80;
        } else if (c >= 0xe0 && c <= 0xef) {
            len = 3; cp = c & 0x0f; min = 0x800;
        } else if (c >= 0xf0 && c <= 0xf4) {
            len = 4; cp = c & 0x07; min = 0x10000;
        } else {
            return 0;
        }
        if (i + len > n)
            return 0;
        for (size_t k = 1; k < len; k++) {
            uint8_t cc = s[i + k];
            if ((cc & 0xc0) != 0x80)
                return 0;
            cp = (cp << 6) | (cc & 0x3f);
        }
        if (cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff))
            return 0;
        i += len;
    }
    return 1;
}
