# CBOR diagnostic notation

Shows CBOR as RFC 8949 section 8 diagnostic notation: the human-readable
form CBOR specifications use for examples. The input is checked first,
exactly as
[`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
checks it, so nothing hostile reaches the printer, and the output is
bounded by the input's size.

## Usage

``` r
cbor_diagnose(
  x,
  sequence = FALSE,
  deterministic = FALSE,
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06
)
```

## Arguments

- x:

  A raw vector.

- sequence:

  If `TRUE`, `x` is an RFC 8742 CBOR sequence of zero or more items; if
  `FALSE`, it must be exactly one item.

- deterministic:

  If `TRUE`, also require RFC 8949 section 4.2.1 core deterministic
  encoding: shortest integers, lengths and floats, definite lengths, map
  keys in bytewise order, and bignums in preferred form.

- duplicate_keys:

  If `FALSE` (the default), a map with the same key twice is invalid.

- max_depth:

  Deepest nesting allowed, counting arrays, maps and tags. At most
  `zucbor_info()$max_depth_cap`.

- max_size:

  Largest input allowed, in bytes, or `Inf`.

- max_items:

  Most data items allowed, counting every tag and every chunk of an
  indefinite-length string, or `Inf`.

## Value

A single string.

## Details

The notation matches RFC 8949's own Appendix A. Numbers print as JSON
and JavaScript print them, with `.0` added to a float that would
otherwise read as an integer (`1.0`, `1.0e+300`). Text is ASCII:
characters beyond it appear as `\u` escapes, as Appendix A writes them.
An indefinite-length item shows `_ ` after its opening bracket, and a
chunked string its chunks as `(_ "a", "b")`. A sequence's items are
separated by commas (RFC 8742 section 4.2).

## See also

[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
to turn CBOR into R values.

## Examples

``` r
cbor_diagnose(as.raw(c(0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03)))
#> [1] "{\"a\": 1, \"b\": [2, 3]}"
cbor_diagnose(cbor_encode(list(when = Sys.Date(), pi = pi, bytes = as.raw(1:4))))
#> [1] "{\"pi\": 3.141592653589793, \"when\": 1004(\"2026-10-01\"), \"bytes\": h'01020304'}"
cbor_diagnose(as.raw(c(0x01, 0xf9, 0x3e, 0x00)), sequence = TRUE)
#> [1] "1, 1.5"
```
