#include <math.h>

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
