# Annotated hex dump of CBOR

Shows where each byte of CBOR goes: one line per head, with its offset,
its bytes in hex, indented by nesting, and what it is. A string's
content follows its head, 16 bytes a line, and the first of those lines
previews it. Every byte of the input appears exactly once in the hex
column. This is the view needed to review a signed message byte by byte;
[`cbor_diagnose()`](https://pedrobtz.github.io/zucbor/reference/cbor_diagnose.md)
shows what the message means instead.

## Usage

``` r
cbor_annotate(
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

A character vector of class `cbor_annotation`, one element per line,
which prints as the lines.

## Details

The input is checked first, exactly as
[`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
checks it. The output is bounded by a constant multiple of the input's
size: previews stop at 32 bytes and indentation at 16 levels.

Offsets are 0-based, in decimal, as in zucbor's error conditions.
Integers show their value (`negative(-501)`), floats their width and
value (`float16 1.5`), and indefinite-length items `(*)` and a
[`break`](https://rdrr.io/r/base/Control.html).

## See also

[`cbor_diagnose()`](https://pedrobtz.github.io/zucbor/reference/cbor_diagnose.md)
for diagnostic notation.

## Examples

``` r
cbor_annotate(as.raw(c(0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03)))
#> 0  a2      # map(2)
#> 1    61    # text(1)
#> 2      61  # "a"
#> 3    01    # unsigned(1)
#> 4    61    # text(1)
#> 5      62  # "b"
#> 6    82    # array(2)
#> 7      02  # unsigned(2)
#> 8      03  # unsigned(3)

# A COSE_Sign1 message's protected header, {1: -7}, inside a byte string.
cbor_annotate(cbor_encode(list(cbor_encode(cbor_map(list(1L), list(-7))), "payload")))
#> 0  82                        # array(2)
#> 1    43                      # bytes(3)
#> 2      a1 01 26              # h'a10126'
#> 5    67                      # text(7)
#> 6      70 61 79 6c 6f 61 64  # "payload"
```
