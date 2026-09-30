# CBOR values without a native R type

Constructors for the four values
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
returns when R has no faithful type of its own. Encoding accepts them
too, to write those values back.

## Usage

``` r
cbor_map(keys = list(), values = list())

cbor_tag(tag, value)

cbor_simple(value)

cbor_bigint(x)
```

## Arguments

- keys, values:

  Lists (or vectors, taken element by element) of equal length.

- tag:

  A whole number from 0 to 2^53.

- value:

  For `cbor_tag()`, the tagged content; for `cbor_simple()`, integer
  simple values.

- x:

  Decimal strings or whole numbers.

## Value

An object of class `cbor_map`, `cbor_tag`, `cbor_simple` or
`cbor_bigint`.

## Details

- `cbor_map()` is a map whose keys are not all non-empty, unique text:
  COSE and CWT use small integers as keys, for example. `keys` and
  `values` are lists of equal length, in order.

- `cbor_tag()` is a tagged item: `tag` is the tag number, `value` its
  content.

- `cbor_simple()` is a simple value other than `false`, `true`, `null`
  and `undefined`: 0 to 19 or 32 to 255.

- `cbor_bigint()` is an integer outside what a double holds exactly,
  stored as canonical decimal text. It accepts decimal strings, or whole
  numbers within 2^53.

## Examples

``` r
cbor_map(list(1L, 3L), list(-7L, "ES256"))
#> <cbor_map: 2 entries>
#> [[1]]
#> [1] -7
#> [[3]]
#> [1] "ES256"
cbor_tag(32, "https://example.com")
#> <cbor_tag 32>
#> [1] "https://example.com"
cbor_simple(16)
#> simple(16)
cbor_bigint("18446744073709551616")
#> <cbor_bigint[1]>
#> [1] 18446744073709551616
```
