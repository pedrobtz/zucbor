# Encode R values as CBOR

Turns an R value into CBOR bytes. The encoding is always RFC 8949
section 4.2.1 core deterministic encoding, so identical R objects give
identical bytes on every platform: the shortest form of every integer,
length and tag number; definite lengths; the shortest float that holds
each value exactly; and map entries sorted by their encoded keys.

## Usage

``` r
cbor_encode(x, auto_unbox = TRUE, self_describe = FALSE, max_depth = 256L)

cbor_encode_seq(x, auto_unbox = TRUE, self_describe = FALSE, max_depth = 256L)
```

## Arguments

- x:

  An R value. For `cbor_encode_seq()`, a list whose elements are encoded
  one after another as an RFC 8742 CBOR sequence.

- auto_unbox:

  If `TRUE`, a length-one atomic vector is a single value; if `FALSE`,
  it is an array of one. Names used as map keys are always single text
  strings.

- self_describe:

  If `TRUE`, prefix each item with the self-describe tag 55799
  (`d9 d9 f7`), which marks bytes as CBOR.

- max_depth:

  Deepest nesting to write, counting arrays, maps and tags as
  [`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
  does, so its output always decodes at the same `max_depth`.

## Value

A raw vector.

## R to CBOR

|  |  |
|----|----|
| R | CBOR |
| `NULL`, `NA` of any type | `null` |
| `TRUE`, `FALSE` | `true`, `false` |
| `integer` | integer |
| `double`, whole, within CBOR's integer range, not `-0` | integer |
| any other `double`, including `NaN`, `Inf` and `-0` | float, shortest exact width |
| `character` | text string, UTF-8 |
| `raw` | one byte string, whatever its length |
| `factor` | its labels, as text |
| `POSIXct` | tag 1: whole seconds as an integer, else a float |
| `Date` | tag 1004 `"YYYY-MM-DD"`; tag 100 (days) outside years 0000-9999 |
| `cbor_bigint` | integer, or tag 2 or 3 beyond CBOR's integer range |
| `cbor_map`, `cbor_tag`, `cbor_simple` | a map, a tagged item, a simple value |
| unnamed list or vector | array |
| fully named list or vector | map with text keys |

A length-one atomic vector is a single value, not an array, unless it is
wrapped in [`I()`](https://rdrr.io/r/base/AsIs.html) or
`auto_unbox = FALSE`. A matrix is a flat array in column-major order. A
vector whose class zucbor does not know is written as its underlying
type.

Whole doubles become integers because R has no integer literal: `-7`
written in R is a double, and as a CBOR float it would be a different
value from the integer a COSE algorithm identifier needs. So `1L` and
`1` encode identically.

These have no CBOR form and raise `zucbor_unsupported_type`: complex
numbers, functions, environments, external pointers, S4 objects,
`POSIXlt` (convert with
[`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html)) and data
frames. Names that are partly missing, `NA` or empty are
`zucbor_invalid_argument`, and two keys that encode identically are
`zucbor_duplicate_key`.

## Conversions that do not round-trip

Decoding what `cbor_encode()` wrote gives back the value, except that:
`NA` comes back as `NULL`, or `NA` of the vector's type; a whole double
comes back as an integer; `list(1L)` and `1L` both encode as `1`; `NaN`
payloads are not kept; and fractional days of a `Date` are dropped.

## See also

[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md),
[cbor-values](https://pedrobtz.github.io/zucbor/reference/cbor-values.md).

## Examples

``` r
cbor_encode(list(a = 1, b = c(2, 3)))
#> [1] a2 61 61 01 61 62 82 02 03
cbor_encode(c(1.5, NaN, Inf))
#>  [1] 83 f9 3e 00 f9 7e 00 f9 7c 00

# A COSE header: integer keys need cbor_map().
cbor_encode(cbor_map(list(1L), list(-7)))
#> [1] a1 01 26

# Deterministic: map entries are sorted by their encoded keys.
identical(cbor_encode(list(b = 1, a = 2)), cbor_encode(list(a = 2, b = 1)))
#> [1] TRUE

cbor_encode_seq(list(1, "a", TRUE))
#> [1] 01 61 61 f5
```
