# Examples

Worked examples for the tasks CBOR is usually used for. Each one runs as
written, with only zucbor and base R.

``` r

library(zucbor)

# CBOR examples are usually written in hex; this turns hex into bytes.
hex <- function(h) {
  h <- gsub("[^0-9a-fA-F]", "", h)
  as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
}
```

## Look at bytes before decoding them

Diagnostic notation is the quickest way to see what a message holds. It
checks the input first, so it is safe on anything:

``` r

msg <- hex("a3 63 74 6d 70 f9 4d 70 62 69 64 1a 00 01 e2 40 62 6f 6b f5")
cbor_diagnose(msg)
#> [1] "{\"tmp\": 21.75, \"id\": 123456, \"ok\": true}"
cbor_validate(msg)
#> [1] TRUE
str(cbor_decode(msg))
#> List of 3
#>  $ tmp: num 21.8
#>  $ id : int 123456
#>  $ ok : logi TRUE
```

A malformed message says what is wrong and where:

``` r

bad <- hex("a3 63 74 6d 70 f9 4d 70 62 69 64")    # cut off mid-way
cbor_validate(bad)
#> [1] FALSE
tryCatch(cbor_validate(bad, error = TRUE),
         zucbor_error = function(e) c(class = class(e)[1], offset = e$offset))
#>                class               offset 
#> "zucbor_parse_error"                 "11"
```

## Maps with integer keys

Protocols built on CBOR save space by using small integers as map keys.
Such a map decodes to a `cbor_map`, which keeps the keys as they are. A
small helper looks values up by key:

``` r

cose_key <- cbor_decode(hex(paste0(
  "a5 01 02 03 26 20 01",
  "21 58 20 65eda5a12577c2bae829437fe338701a10aaa375e1bb5b5de108de439c08551d",
  "22 58 20 1e52ed75701163f7f9e40ddf9f341b3dc9ba860af7e0ca7ca7e9eecd0084d19c")))
cose_key
#> <cbor_map: 5 entries>
#> [[1]]
#> [1] 2
#> [[3]]
#> [1] -7
#> [[-1]]
#> [1] 1
#> [[-2]]
#>  [1] 65 ed a5 a1 25 77 c2 ba e8 29 43 7f e3 38 70 1a 10 aa a3 75 e1 bb 5b 5d e1
#> [26] 08 de 43 9c 08 55 1d
#> [[-3]]
#>  [1] 1e 52 ed 75 70 11 63 f7 f9 e4 0d df 9f 34 1b 3d c9 ba 86 0a f7 e0 ca 7c a7
#> [26] e9 ee cd 00 84 d1 9c

get <- function(map, key) {
  m <- unclass(map)
  hit <- vapply(m$keys, identical, logical(1), key)
  if (any(hit)) m$values[[which(hit)[1]]] else NULL
}
get(cose_key, 3L)      # alg: -7, ES256
#> [1] -7
get(cose_key, -1L)     # crv: 1, P-256
#> [1] 1
```

`map_keys = "string"` names every entry instead, turning non-text keys
into their diagnostic notation. It is handy for exploring, but lossy:
`1` and `"1"` would collide, and zucbor refuses that rather than drop
one.

``` r

names(cbor_decode(hex("a3 01 02 03 26 20 01"), map_keys = "string"))
#> [1] "1"  "3"  "-1"
```

To write such a map, build it with
[`cbor_map()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md).
Whole numbers are written as integers even when R holds them as doubles,
as the protocol needs:

``` r

hdr <- cbor_map(list(1L, 4L), list(-7, charToRaw("key-1")))
cbor_diagnose(cbor_encode(hdr))
#> [1] "{1: -7, 4: h'6b65792d31'}"
```

## Integers beyond 2^53

A double holds integers exactly only up to 2^53. Wider ones, such as
64-bit identifiers or nanosecond timestamps, decode to `cbor_bigint`,
which keeps every digit:

``` r

id <- cbor_decode(hex("1b 16 f8 44 1f 3b 6f 00 01"))
id
#> <cbor_bigint[1]>
#> [1] 1655147763990462465
as.character(id)
#> [1] "1655147763990462465"
cbor_encode(id)                           # the same nine bytes back
#> [1] 1b 16 f8 44 1f 3b 6f 00 01
cbor_decode(hex("1b 16 f8 44 1f 3b 6f 00 01"), big_integers = "double")
#> [1] 1.655148e+18
```

## Dates and times

Tags 0 and 1 are instants and decode to `POSIXct` in UTC; tags 100 and
1004 are calendar days and decode to `Date`. `POSIXct` is written back
as tag 1, `Date` as tag 1004:

``` r

cbor_decode(hex("c0 74 32 30 31 33 2d 30 33 2d 32 31 54 32 30 3a 30 34 3a 30 30 5a"))
#> [1] "2013-03-21 20:04:00 UTC"
cbor_decode(hex("c1 1a 51 4b 67 b0"))
#> [1] "2013-03-21 20:04:00 UTC"
when <- as.POSIXct("2026-09-30 12:00:00", tz = "UTC")
cbor_diagnose(cbor_encode(list(seen = when, day = as.Date(when))))
#> [1] "{\"day\": 1004(\"2026-09-30\"), \"seen\": 1(1790769600)}"
```

Other tags come back as `cbor_tag`, with the number and the content:

``` r

uri <- cbor_decode(hex("d8 20 76 68 74 74 70 3a 2f 2f 77 77 77 2e 65 78 61 6d 70 6c 65 2e 63 6f 6d"))
uri$tag
#> [1] 32
uri$value
#> [1] "http://www.example.com"
```

## CBOR inside CBOR

COSE and CWT carry CBOR inside byte strings, and tag 24 marks embedded
CBOR. zucbor never decodes those on its own; decoding them is one
explicit call, with its own checks and limits:

``` r

outer <- cbor_decode(hex("d8 18 45 82 01 61 61 00"))
outer
#> <cbor_tag 24>
#> [1] 82 01 61 61 00
```

That tagged byte string is five bytes of CBOR followed by one more byte,
so
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
refuses it, while
[`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
reads both items:

``` r

inner <- hex("82 01 61 61 00")
tryCatch(cbor_decode(inner), zucbor_error = function(e) class(e)[1])
#> [1] "zucbor_parse_error"
cbor_decode_seq(inner)
#> [[1]]
#> [[1]][[1]]
#> [1] 1
#> 
#> [[1]][[2]]
#> [1] "a"
#> 
#> 
#> [[2]]
#> [1] 0
```

## Telemetry as a data frame

Sensors often send records one after another as an RFC 8742 sequence.
Records with the same text keys become named lists, and a data frame is
one step away:

``` r

readings <- lapply(1:5, function(i) list(sensor = paste0("t", i %% 2), c = 20 + i / 4, ok = i != 3))
stream <- cbor_encode_seq(readings)
length(stream)
#> [1] 98

records <- cbor_decode_seq(stream)
do.call(rbind, lapply(records, as.data.frame))
#>       c    ok sensor
#> 1 20.25  TRUE     t1
#> 2 20.50  TRUE     t0
#> 3 20.75 FALSE     t1
#> 4 21.00  TRUE     t0
#> 5 21.25  TRUE     t1
```

The columns come back as `c`, `ok`, `sensor`, not in the order the lists
were built: deterministic encoding writes map keys sorted by their
encoded bytes, shorter keys first, and decoding keeps the order it
reads. Select columns by name when order matters.

## Files and connections

[`cbor_read()`](https://pedrobtz.github.io/zucbor/reference/cbor_read.md)
reads a file, a URL or a connection, and never reads more than
`max_size + 1` bytes, so a huge or endless source fails quickly:

``` r

path <- tempfile(fileext = ".cbor")
writeBin(cbor_encode(list(version = 2L, tags = c("a", "b"))), path)
cbor_read(path)     # keys in encoded order: "tags" is shorter than "version"
#> $tags
#> [1] "a" "b"
#> 
#> $version
#> [1] 2

tryCatch(cbor_read(path, max_size = 8), zucbor_limit_error = function(e) e$limit)
#> [1] "max_size"
unlink(path)
```

An open connection is read from its current position and left open, so a
header can be read by hand first:

``` r

con <- rawConnection(c(charToRaw("CBOR"), cbor_encode(1:3)))
readBin(con, "raw", n = 4)        # a 4-byte header, say
#> [1] 43 42 4f 52
cbor_read(con)
#> [1] 1 2 3
close(con)
```

## Limits for untrusted input

The defaults suit messages from a network peer. Tighten them for small,
known messages, or loosen them for large trusted files:

``` r

nested <- c(rep(as.raw(0x81), 20), as.raw(0x00))    # 20 nested arrays
tryCatch(cbor_decode(nested, max_depth = 8), zucbor_limit_error = function(e) conditionMessage(e))
#> [1] "CBOR nested deeper than max_depth = 8 at byte 8"

big <- cbor_encode(as.list(1:5000))
tryCatch(cbor_decode(big, max_items = 1000), zucbor_limit_error = function(e) class(e)[1])
#> [1] "zucbor_item_limit"
length(cbor_decode(big, max_items = Inf))
#> [1] 5000
```

Duplicate map keys are refused by default, compared by value, so a key
written twice in different lengths is still caught:

``` r

dup <- hex("a2 01 00 18 01 00")      # {1: 0, 1: 0}, the second key two bytes long
tryCatch(cbor_decode(dup), zucbor_duplicate_key = function(e) conditionMessage(e))
#> [1] "duplicate map key at byte 3"
```

## Bytes that must not change

A signature covers bytes. Deterministic encoding means that decoding a
deterministic message and encoding it again gives exactly those bytes,
so a signed structure can be taken apart, checked and rebuilt safely:

``` r

signed <- hex("84 43 a1 01 26 a0 45 68 65 6c 6c 6f 40")
cbor_validate(signed, deterministic = TRUE)
#> [1] TRUE
identical(cbor_encode(cbor_decode(signed)), signed)
#> [1] TRUE
```

Order does not leak into the bytes: two lists with the same entries
encode identically, whatever order they were built in.

``` r

identical(cbor_encode(list(b = 2, a = 1)), cbor_encode(list(a = 1, b = 2)))
#> [1] TRUE
```

A one-element array comes back marked with
[`I()`](https://rdrr.io/r/base/AsIs.html), which is what keeps its
brackets when it is encoded again:

``` r

one <- cbor_decode(hex("a1 63 78 35 63 81 42 01 02"))    # {"x5c": [h'0102']}
str(one)
#> List of 1
#>  $ x5c:List of 1
#>   ..$ : raw [1:2] 01 02
cbor_encode(one)
#> [1] a1 63 78 35 63 81 42 01 02
```
