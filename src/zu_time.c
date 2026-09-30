/* Dates and times for tags 0, 1004 and 100 (design section 6.7), without
 * strptime(), so results do not vary by platform or locale. Calendar
 * arithmetic is Howard Hinnant's days_from_civil, as in zujson. */
#include "zucbor.h"

/* Days since 1970-01-01 of a proleptic Gregorian date. */
static double days_from_civil(long y, int m, int d)
{
    y -= m <= 2;
    long era = (y >= 0 ? y : y - 399) / 400;
    long yoe = y - era * 400;
    long doy = (153L * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return (double)(era * 146097 + doe - 719468);
}

static int is_leap(long y)
{
    return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
}

static int days_in_month(long y, int m)
{
    static const int dim[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return m == 2 && is_leap(y) ? 29 : dim[m - 1];
}

/* n decimal digits at s[*pos], advancing *pos; -1 if any is not a digit. */
static long digits(const char *s, size_t len, size_t *pos, int n)
{
    long v = 0;
    if (*pos + (size_t)n > len)
        return -1;
    for (int i = 0; i < n; i++) {
        char c = s[*pos + (size_t)i];
        if (c < '0' || c > '9')
            return -1;
        v = v * 10 + (c - '0');
    }
    *pos += (size_t)n;
    return v;
}

static int expect(const char *s, size_t len, size_t *pos, char c)
{
    if (*pos >= len || s[*pos] != c)
        return 0;
    (*pos)++;
    return 1;
}

/* YYYY-MM-DD at s[*pos]; 0 on success. */
static int full_date(const char *s, size_t len, size_t *pos, long *y, int *m, int *d)
{
    *y = digits(s, len, pos, 4);
    if (*y < 0 || !expect(s, len, pos, '-'))
        return 1;
    long mm = digits(s, len, pos, 2);
    if (mm < 1 || mm > 12 || !expect(s, len, pos, '-'))
        return 1;
    long dd = digits(s, len, pos, 2);
    if (dd < 1 || dd > days_in_month(*y, (int) mm))
        return 1;
    *m = (int) mm;
    *d = (int) dd;
    return 0;
}

/* RFC 8943 full-date: exactly YYYY-MM-DD. Days since the epoch. */
int zu_parse_full_date(const char *s, size_t len, double *days)
{
    size_t pos = 0;
    long y;
    int m, d;
    if (full_date(s, len, &pos, &y, &m, &d) || pos != len)
        return 1;
    *days = days_from_civil(y, m, d);
    return 0;
}

/* RFC 3339 date-time, as tag 0 requires (RFC 8949 section 3.4.1): seconds
 * since the epoch, offsets applied, fractional seconds kept. A leap second
 * (:60) is accepted, as RFC 3339 allows, and lands on the next second. */
int zu_parse_rfc3339(const char *s, size_t len, double *secs)
{
    size_t pos = 0;
    long y;
    int m, d;
    if (full_date(s, len, &pos, &y, &m, &d))
        return 1;
    if (pos >= len || (s[pos] != 'T' && s[pos] != 't'))
        return 1;
    pos++;
    long hh = digits(s, len, &pos, 2);
    if (hh < 0 || hh > 23 || !expect(s, len, &pos, ':'))
        return 1;
    long mi = digits(s, len, &pos, 2);
    if (mi < 0 || mi > 59 || !expect(s, len, &pos, ':'))
        return 1;
    long ss = digits(s, len, &pos, 2);
    if (ss < 0 || ss > 60)
        return 1;
    double frac = 0, scale = 0.1;
    if (pos < len && s[pos] == '.') {
        pos++;
        size_t first = pos;
        while (pos < len && s[pos] >= '0' && s[pos] <= '9') {
            frac += (s[pos] - '0') * scale;
            scale /= 10;
            pos++;
        }
        if (pos == first)
            return 1;
    }
    long offset = 0;
    if (pos < len && (s[pos] == 'Z' || s[pos] == 'z')) {
        pos++;
    } else if (pos < len && (s[pos] == '+' || s[pos] == '-')) {
        int sign = s[pos] == '-' ? -1 : 1;
        pos++;
        long oh = digits(s, len, &pos, 2);
        if (oh < 0 || oh > 23 || !expect(s, len, &pos, ':'))
            return 1;
        long om = digits(s, len, &pos, 2);
        if (om < 0 || om > 59)
            return 1;
        offset = sign * (oh * 3600 + om * 60);
    } else {
        return 1;
    }
    if (pos != len)
        return 1;
    *secs = days_from_civil(y, m, d) * 86400.0 + (double)(hh * 3600 + mi * 60 + ss)
            - (double) offset + frac;
    return 0;
}
