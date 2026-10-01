# Conditions raised by zucbor

Every error zucbor raises carries a condition class, so it can be caught
by kind rather than by matching the message, which may change. Every
class below inherits from `zucbor_error`.

## Details

- `zucbor_invalid_argument`:

  An argument was unusable: an input that is not a raw vector, a flag
  that is not `TRUE` or `FALSE`, a limit that is not a positive whole
  number within its range, or a value
  [`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
  cannot write as given, such as partial names or a string that is not
  valid UTF-8.

- `zucbor_parse_error`:

  The input is not well-formed CBOR: it ends early, uses a reserved
  encoding, has a misplaced "break", or has bytes after the item.

- `zucbor_invalid_error`:

  The input is well-formed but not valid: a text string that is not
  UTF-8, a tag whose content has the wrong type, a typed array whose
  length is not a whole number of elements, or a multi-dimensional array
  whose shape does not match its elements.

- `zucbor_deterministic_error`:

  `deterministic = TRUE` and the input is not in RFC 8949 core
  deterministic encoding.

- `zucbor_duplicate_key`:

  A map has the same key twice and `duplicate_keys = FALSE`.

- `zucbor_unrepresentable`:

  The input is valid CBOR but holds a value R cannot: a text string
  containing U+0000 or longer than an R string, a tag number beyond
  2^53, an integer beyond 2^53 with `big_integers = "error"`, or an
  array dimension beyond R's limit.

- `zucbor_unsupported_type`:

  [`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
  was given an R value with no CBOR form, such as a function, an
  environment, `POSIXlt` or a data frame.

- `zucbor_handler_error`:

  A function in
  [`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)'s
  `tag_handlers` raised an error. The condition carries `tag`, the tag
  number, and `parent`, the error the handler raised.

- `zucbor_limit_error`:

  A limit was reached. The subclasses `zucbor_depth_limit`,
  `zucbor_size_limit` and `zucbor_item_limit` name which one.

A condition raised while checking input carries `offset`, the 0-based
byte offset of the item at fault, or `NA` when the validator that found
the fault reports no position; and `status`, the name of the underlying
status, such as `"CborErrorUnexpectedEOF"`. It is there for diagnostics:
branch on the class, not on it. A limit error also carries `limit`, the
argument's name, such as `"max_depth"`, and `limit_value`. A
`zucbor_invalid_argument` condition carries `arg`, the argument at
fault.

## Examples

``` r
tryCatch(
  cbor_validate(as.raw(c(0x82, 0x01)), error = TRUE),
  zucbor_parse_error = function(e) e$offset
)
#> [1] 2
```
