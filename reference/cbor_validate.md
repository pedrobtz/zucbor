# Validate CBOR

Checks that `x` holds well-formed, valid CBOR within the given limits,
without building any R value. This is exactly the check `cbor_decode()`
runs before it builds anything, so the two agree about the bytes; they
disagree only where the bytes are valid but R cannot hold the value,
such as a text string containing U+0000.

## Usage

``` r
cbor_validate(
  x,
  sequence = FALSE,
  deterministic = FALSE,
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06,
  error = FALSE
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

- error:

  If `TRUE`, raise the classed condition describing the fault instead of
  returning `FALSE`; see
  [zucbor-conditions](https://pedrobtz.github.io/zucbor/reference/zucbor-conditions.md).

## Value

`TRUE` or `FALSE`; with `error = TRUE`, `TRUE` invisibly or an error.

## Details

The check covers well-formedness (RFC 8949 section 3), UTF-8 in text
strings, the content type of the tags TinyCBOR knows, duplicate map keys
(compared by value, so `1` encoded in one byte and in two is the same
key), and the limits.

## Examples

``` r
cbor_validate(as.raw(c(0x83, 0x01, 0x02, 0x03)))   # [1, 2, 3]
#> [1] TRUE
cbor_validate(as.raw(c(0x83, 0x01, 0x02)))         # truncated
#> [1] FALSE
cbor_validate(as.raw(c(0xa2, 0x01, 0x00, 0x01, 0x00)))  # {1: 0, 1: 0}
#> [1] FALSE
cbor_validate(as.raw(c(0x01, 0x02)), sequence = TRUE)
#> [1] TRUE
```
