# Decode the CBOR item at the start of a raw vector

Decodes the one CBOR data item that `x` starts with and reports how many
bytes it used, for CBOR inside binary framing: a COSE key in the middle
of WebAuthn `authData`, or a payload after a fixed header. The item is
checked and decoded exactly as by
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md),
with the same arguments; what follows it is not read at all.

## Usage

``` r
cbor_decode_prefix(
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

  A raw vector starting with a CBOR data item.

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

A list: `value`, the decoded item, and `consumed`, the number of bytes
it took, a double.

## Details

That also means nothing about the rest is known: it may be more CBOR, or
the next field of the framing, or garbage. It is the caller's to make
sense of, as `x[-seq_len(consumed)]`.

`max_size` applies to `x` as a whole, since all of it is in memory
already. An empty `x` is `zucbor_parse_error`, as for
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md);
so is an item cut short by the end of `x`.

## See also

[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
for one item and nothing else, and
[`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
for items all the way to the end.

## Examples

``` r
# [1, 2] followed by four bytes of something else.
x <- as.raw(c(0x82, 0x01, 0x02, 0xde, 0xad, 0xbe, 0xef))
r <- cbor_decode_prefix(x)
r$value
#> [1] 1 2
x[-seq_len(r$consumed)]
#> [1] de ad be ef
```
