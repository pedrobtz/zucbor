# Decoding untrusted CBOR

CBOR usually arrives from somewhere you do not control: a network peer,
a sensor, a browser relaying an authenticator. zucbor treats every input
as hostile, and this vignette shows what that means in practice.

``` r

library(zucbor)
hex <- function(h) as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
```

## Check first, build second

[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
works in two phases. The first walks the whole input and checks it:
well-formedness, UTF-8, the content of the tags it knows, duplicate map
keys and the limits. Only when all of that passes does the second phase
build R values. So a nine-byte header that claims an array of 2^64 − 1
elements is refused before R allocates anything:

``` r

tryCatch(cbor_decode(hex("9bffffffffffffffff")),
         zucbor_error = function(e) conditionMessage(e))
#> [1] "CBOR parse error at byte 0: unexpected end of data"
```

[`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
runs exactly that first phase and nothing else. It returns `TRUE` or
`FALSE`; with `error = TRUE` it raises the condition that explains a
`FALSE`:

``` r

cbor_validate(hex("830102"))
#> [1] FALSE
tryCatch(cbor_validate(hex("830102"), error = TRUE), zucbor_error = function(e) e$offset)
#> [1] 3
```

The two agree about the bytes. They disagree only where the bytes are
valid CBOR that R cannot hold, such as a text string containing U+0000,
which
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
refuses with `zucbor_unrepresentable`.

## Limits

Three limits bound what an input can cost.

| Limit       | Default   | What it bounds                                  |
|-------------|-----------|-------------------------------------------------|
| `max_size`  | 64 MiB    | the input, in bytes                             |
| `max_depth` | 256       | nesting of arrays, maps and tags (at most 1023) |
| `max_items` | 1,000,000 | data items, counting every tag and string chunk |

`max_items` matters even though `max_size` bounds the input: one byte of
CBOR can become dozens of bytes of R objects, so 64 MiB of empty arrays
would otherwise ask R for gigabytes.

``` r

deep <- c(rep(as.raw(0x81), 300), as.raw(0x00))    # [[[...[0]...]]]
tryCatch(cbor_decode(deep), zucbor_limit_error = function(e) c(e$limit, e$limit_value))
#> [1] "max_depth" "256"
tryCatch(cbor_decode(hex("83010203"), max_items = 3),
         zucbor_limit_error = function(e) class(e)[1])
#> [1] "zucbor_item_limit"
```

[`cbor_read()`](https://pedrobtz.github.io/zucbor/reference/cbor_read.md)
reads a file, URL or connection, and never reads more than
`max_size + 1` bytes, so an endless stream fails instead of filling
memory. A log or a socket that is a long CBOR sequence is read item by
item with `cbor_read_seq(each =)`: then `max_size` bounds each item
rather than the stream, and each item is still checked whole before it
is built.

## Duplicate map keys

RFC 8949 leaves duplicate keys to the application, and they are a
classic way to make two parsers of the same signed structure see
different values. zucbor refuses them by default, comparing keys by
value: the integer 1 written in one byte and in two is the same key.

``` r

cbor_validate(hex("a2010018010000"))          # {1: 0, 1: 0}, the second 1 longer
#> [1] FALSE
cbor_decode(hex("a2616101616102"), duplicate_keys = TRUE)   # {"a": 1, "a": 2}
#> <cbor_map: 2 entries>
#> [[a]]
#> [1] 1
#> [[a]]
#> [1] 2
```

When duplicates are allowed, the map comes back as a `cbor_map`, which
keeps both entries in order; a named list could not say which was which.

## Deterministic input

Some protocols require a single encoding for each value, so that a
re-encoded structure matches what was signed. `deterministic = TRUE`
refuses anything that is not RFC 8949 core deterministic encoding: the
shortest integers, lengths and floats, definite lengths, map keys in
bytewise order and bignums in preferred form.

``` r

cbor_validate(hex("1801"), deterministic = TRUE)       # 1 in two bytes
#> [1] FALSE
cbor_validate(hex("a203040102"), deterministic = TRUE) # keys out of order
#> [1] FALSE
```

Everything
[`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
writes passes that check, and decoding then encoding deterministic input
gives back the same bytes.

## Handling errors

Every error is a condition inheriting `zucbor_error`, so one handler can
catch them all, and its subclass says what went wrong:

``` r

classify <- function(x) tryCatch({cbor_decode(x); "ok"}, zucbor_error = function(e) class(e)[1])
vapply(list(hex("8201"), hex("61ff"), hex("a201000100"), hex("6100"), hex("0102")), classify, "")
#> [1] "zucbor_parse_error"     "zucbor_invalid_error"   "zucbor_duplicate_key"  
#> [4] "zucbor_unrepresentable" "zucbor_parse_error"
```

Conditions raised while checking input also carry `offset`, the byte
offset of the fault, and `status`, the name of the underlying status.
See
[`?"zucbor-conditions"`](https://pedrobtz.github.io/zucbor/reference/zucbor-conditions.md)
for the whole hierarchy.
