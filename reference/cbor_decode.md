# Decode CBOR

Turns CBOR bytes into ordinary R values. The whole input is checked
first – well-formedness, validity, duplicate keys and the limits,
exactly as
[`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
does – and nothing is built until that check passes, so a length header
cannot make R allocate for data the input does not hold.

## Usage

``` r
cbor_decode(
  x,
  simplify = c("preserve", "none"),
  map_keys = c("auto", "map", "string"),
  tags = c("convert", "keep"),
  big_integers = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  deterministic = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06,
  tag_handlers = NULL,
  data_frame = FALSE,
  max_cells = 1e+07
)

cbor_decode_seq(
  x,
  simplify = c("preserve", "none"),
  map_keys = c("auto", "map", "string"),
  tags = c("convert", "keep"),
  big_integers = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  deterministic = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06,
  tag_handlers = NULL,
  data_frame = FALSE,
  max_cells = 1e+07
)
```

## Arguments

- x:

  A raw vector holding exactly one CBOR data item (`cbor_decode()`), or
  an RFC 8742 sequence of zero or more (`cbor_decode_seq()`).

- simplify:

  `"preserve"` simplifies arrays whose elements agree to atomic vectors;
  `"none"` makes every array a list.

- map_keys:

  `"auto"` gives a named list when every key is a non-empty, unique text
  string, and a `cbor_map` otherwise. `"map"` always gives a `cbor_map`.
  `"string"` always gives a named list, naming each entry by its text
  key, or by the key's diagnostic notation when it is not text; it is
  lossy, and refuses a map whose keys collide once stringified.

- tags:

  `"convert"` turns the tags in the table into R values and keeps the
  rest as `cbor_tag`; `"keep"` makes every tag a `cbor_tag`.

- big_integers:

  What to do with an integer beyond 2^53, which a double cannot hold
  exactly: `"bigint"` returns a `cbor_bigint`, `"double"` the nearest
  double, and `"error"` refuses the input.

- duplicate_keys:

  If `FALSE` (the default), a map with the same key twice is invalid.

- deterministic:

  If `TRUE`, also require RFC 8949 section 4.2.1 core deterministic
  encoding: shortest integers, lengths and floats, definite lengths, map
  keys in bytewise order, and bignums in preferred form.

- max_depth:

  Deepest nesting allowed, counting arrays, maps and tags. At most
  `zucbor_info()$max_depth_cap`.

- max_size:

  Largest input allowed, in bytes, or `Inf`.

- max_items:

  Most data items allowed, counting every tag and every chunk of an
  indefinite-length string, or `Inf`.

- tag_handlers:

  `NULL`, or a list of functions of one argument, named by tag number,
  such as `list("37" = function(value) ...)`. See "Tag handlers".

- data_frame:

  If `TRUE`, an array whose elements are all maps with text keys becomes
  a data frame. See "Data frames".

- max_cells:

  With `data_frame = TRUE`, the most cells (rows times columns) one data
  frame may have, or `Inf`. Checked before the frame is allocated: rows
  that share no keys make a frame quadratic in the input.

## Value

The decoded value; for `cbor_decode_seq()`, a list with one element per
item.

## CBOR to R

|  |  |
|----|----|
| CBOR | R |
| integer | `integer` if it fits, else `double` up to 2^53, else by `big_integers` |
| float (half, single, double) | `double`, exactly |
| `false` / `true` | `logical` |
| `null`, `undefined` | `NULL`, or `NA` inside an atomic vector |
| byte string | `raw` |
| text string | `character`, UTF-8 |
| other simple value | `cbor_simple` |
| array | atomic vector when the elements agree, else `list` |
| map with non-empty, unique text keys | named `list` |
| any other map | `cbor_map` (by `map_keys`) |
| array of maps with non-empty, unique text keys | `data.frame`, with `data_frame = TRUE` |
| tag 0 (date/time text), tag 1 (epoch) | `POSIXct`, UTC |
| tag 2, 3 (bignum) | the integer it holds, as for an integer; payloads over 128 bytes stay `cbor_tag` |
| tag 100 (days), tag 1004 (full date) | `Date` |
| tag 55799 (self-describe) | its content |
| tags 64-82, 84-86 (RFC 8746 typed arrays) | `integer` (8- and 16-bit, signed 32-bit) or `double`; 64-bit beyond 2^53 by `big_integers` |
| tags 1040, 40 (multi-dimensional arrays) | `matrix` or `array`, in R's column-major order |
| any other tag | `cbor_tag` |

An array simplifies to an atomic vector only when its elements agree:
integers and floats combine to the wider; booleans stay logical, and
text stays text; wide integers and integer-valued numbers combine to
`cbor_bigint`; `POSIXct` and `Date` stay their class. `null` joins any
of them as `NA`. Anything else – raw vectors, nested arrays and maps,
tags, booleans with numbers, a mixture – is a list. `[]` is
`logical(0)`.

A one-element array that simplifies is marked with
[`I()`](https://rdrr.io/r/base/AsIs.html), so that
[`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
writes it back as an array rather than a single value: decoding and then
encoding gives the same bytes for input in deterministic form, apart
from the lossy conversions listed in
[`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md).

`null` and `undefined` both decode as missing: R has one missing value.

## Tag handlers

`tag_handlers` gives meaning to tags zucbor does not convert, or
replaces a conversion it does make. Each handler is called with the
tag's content, decoded with the same options, and its result takes the
tag's place:

    cbor_decode(x, tag_handlers = list(
      "37" = function(value) my_uuid(value),            # RFC 9562 UUID
      "0"  = function(value) value                      # keep the text
    ))

A handler runs only once the whole input has been checked, so it never
sees bytes that are malformed, invalid or over a limit. Its result never
joins an array's simplification: an array holding one is a list. A
handler applies whatever `tags` says, and a tag without one follows
`tags`. An error in a handler becomes `zucbor_handler_error`, with the
tag number as `tag` and the original condition as `parent`. A handler
that calls `cbor_decode()` again, for CBOR embedded in a byte string,
passes that call its own limits.
[`as_cbor()`](https://pedrobtz.github.io/zucbor/reference/as_cbor.md) is
the encoding half.

## Data frames

With `data_frame = TRUE`, an array whose elements are all maps that
decode to named lists – every key a non-empty text string, none twice –
becomes a data frame, one row per map, as
[`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
writes one. Its columns are the union of the maps' keys, in the order
they are first seen; a key a row lacks is missing there, as `null` is.
Each column simplifies as an array of its cells would, so a column of
numbers is numeric and a column of mixed values is a list (in which a
missing cell is `NULL`). An empty array stays `logical(0)`, and an array
holding anything other than such maps decodes as usual.

Rows that share no keys make a frame with as many columns as rows, so
the cell count is checked against `max_cells` before the frame is
allocated, and a frame over it is `zucbor_cell_limit`.

    # SenML (RFC 8428): a pack of records.
    cbor_decode(x, data_frame = TRUE)

## See also

[`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md),
[`as_cbor()`](https://pedrobtz.github.io/zucbor/reference/as_cbor.md),
[`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md),
[`cbor_read()`](https://pedrobtz.github.io/zucbor/reference/cbor_read.md),
[cbor-values](https://pedrobtz.github.io/zucbor/reference/cbor-values.md),
[zucbor-conditions](https://pedrobtz.github.io/zucbor/reference/zucbor-conditions.md).

## Examples

``` r
cbor_decode(as.raw(c(0x83, 0x01, 0x02, 0x03)))        # [1, 2, 3]
#> [1] 1 2 3
cbor_decode(as.raw(c(0xa1, 0x61, 0x61, 0xf5)))        # {"a": true}
#> $a
#> [1] TRUE
#> 

# A COSE header: integer keys, so a cbor_map.
hdr <- cbor_decode(as.raw(c(0xa1, 0x01, 0x26)))       # {1: -7}
hdr
#> <cbor_map: 1 entry>
#> [[1]]
#> [1] -7

cbor_decode_seq(as.raw(c(0x01, 0x61, 0x61)))          # 1, then "a"
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
#> 
```
