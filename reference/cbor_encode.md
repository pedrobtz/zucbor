# Encode R values as CBOR

Turns an R value into CBOR bytes. The encoding is always RFC 8949
section 4.2.1 core deterministic encoding, so identical R objects give
identical bytes on every platform: the shortest form of every integer,
length and tag number; definite lengths; the shortest float that holds
each value exactly; and map entries sorted by their encoded keys.

## Usage

``` r
cbor_encode(
  x,
  auto_unbox = TRUE,
  self_describe = FALSE,
  max_depth = 256L,
  typed_arrays = FALSE
)

cbor_encode_seq(
  x,
  auto_unbox = TRUE,
  self_describe = FALSE,
  max_depth = 256L,
  typed_arrays = FALSE
)
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

- typed_arrays:

  If `TRUE`, write numeric vectors, matrices and arrays as RFC 8746
  typed arrays: see "Typed arrays". Off by default, since many decoders
  do not read them.

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
| data frame | array of maps, one per row, keyed by column name |

A length-one atomic vector is a single value, not an array, unless it is
wrapped in [`I()`](https://rdrr.io/r/base/AsIs.html) or
`auto_unbox = FALSE`. A matrix is a flat array in column-major order. An
object whose class zucbor does not know goes through
[`as_cbor()`](https://pedrobtz.github.io/zucbor/reference/as_cbor.md)
first, so a method can say how to write it; without one it is written as
its underlying type.

Whole doubles become integers because R has no integer literal: `-7`
written in R is a double, and as a CBOR float it would be a different
value from the integer a COSE algorithm identifier needs. So `1L` and
`1` encode identically.

These have no CBOR form and raise `zucbor_unsupported_type`: complex
numbers, functions, environments, external pointers, S4 objects,
`POSIXlt` (convert with
[`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html)), and data
frame columns that are matrices, data frames or raw vectors. Names that
are partly missing, `NA` or empty are `zucbor_invalid_argument`, and two
keys that encode identically are `zucbor_duplicate_key`.

A
[`cbor_tag()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md)
is written as given, but its content must be what
[`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
accepts under that tag number: text under tag 0 must be an RFC 3339
date/time, a typed array a whole number of elements, and so on; anything
else is `zucbor_invalid_argument`. Under a tag whose content cannot be
an array, a length-one vector is one value even with
`auto_unbox = FALSE`. Tags 2 and 3 are written in preferred form,
without leading zero bytes, and as a plain integer when the value fits
in 64 bits.

## Data frames

A data frame is written row by row, as `zujson` writes one: an array of
maps, each keyed by the column names, so `data.frame(a = 1:2)` is
`[{"a": 1}, {"a": 2}]`. A cell is written as the same element of its
column would be in a vector, `NA` as `null`, and a list column's cell as
a value of its own. Row names are dropped. A column of a class zucbor
does not know goes through
[`as_cbor()`](https://pedrobtz.github.io/zucbor/reference/as_cbor.md)
whole, once. `cbor_decode(x, data_frame = TRUE)` reads such an array
back as a data frame.

## Typed arrays

With `typed_arrays = TRUE`, an `integer` or `double` vector that would
be written as an array (not a single value) is one tagged byte string
instead of one item per element: tag 78 (32-bit signed integers) or tag
86 (64-bit floats), little-endian on every platform. Every bit is kept:
`NA_integer_` is written as the smallest 32-bit integer, which decodes
to `NA_integer_` again, and `NA_real_`, `NaN` and `-0` keep their bits.
A whole double stays a float, unlike in an array. A matrix or array, of
any type, is tag 1040: its dimensions and its elements in R's
column-major order, the elements a typed array when they are numeric.
Vectors with a class, such as factors and dates, are written as without
the option.

For 10^6 doubles, a typed array is 8 MB against 9 MB as an array, and is
written and read several times faster.

## Conversions that do not round-trip

Decoding what `cbor_encode()` wrote gives back the value, except that:
`NA` comes back as `NULL`, or `NA` of the vector's type; a whole double
comes back as an integer; `list(1L)` and `1L` both encode as `1`; `NaN`
payloads are not kept; fractional days of a `Date` are dropped; and a
data frame comes back, with `data_frame = TRUE`, without its row names,
with factors as text, and with its columns in the encoded key order; a
`POSIXct` comes back in UTC, whatever its `tzone`; attributes other than
names, `dim` and class are dropped; `cbor_tag(55799, v)` comes back as
`v`; and a `cbor_bigint`, or a tag 2 or 3, whose value fits in 64 bits
comes back as an integer or a double.

## See also

[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md),
[`as_cbor()`](https://pedrobtz.github.io/zucbor/reference/as_cbor.md),
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
