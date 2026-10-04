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

## Where each byte goes

A signature covers bytes, so reviewing a signed message sometimes means
reading it byte by byte.
[`cbor_annotate()`](https://pedrobtz.github.io/zucbor/reference/cbor_annotate.md)
prints one line per head, with its offset, its bytes and what it is.
This is a COSE_Sign1 message from the COSE working group’s examples
(`sign1-tests/sign-pass-01.json`):

``` r

sign1 <- hex(paste0(
  "d28441a0a201260442313154546869732069732074686520636f6e74656e742e5840",
  "87db0d2e5571843b78ac33ecb2830df7b6e0a4d5b7376de336b23c591c90c425317e",
  "56127fbe04370097ce347087b233bf722b64072beb4486bda4031d27244f"))
cbor_annotate(sign1)
#>  0  d2                                                     # tag(18)
#>  1    84                                                   # array(4)
#>  2      41                                                 # bytes(1)
#>  3        a0                                               # h'a0'
#>  4      a2                                                 # map(2)
#>  5        01                                               # unsigned(1)
#>  6        26                                               # negative(-7)
#>  7        04                                               # unsigned(4)
#>  8        42                                               # bytes(2)
#>  9          31 31                                          # h'3131'
#> 11      54                                                 # bytes(20)
#> 12        54 68 69 73 20 69 73 20 74 68 65 20 63 6f 6e 74  # h'546869732069732074686520636f6e74656e742e'
#> 28        65 6e 74 2e
#> 32      58 40                                              # bytes(64)
#> 34        87 db 0d 2e 55 71 84 3b 78 ac 33 ec b2 83 0d f7  # h'87db0d2e5571843b78ac33ecb2830df7b6e0a4d5b7376de336b23c591c90c425'...
#> 50        b6 e0 a4 d5 b7 37 6d e3 36 b2 3c 59 1c 90 c4 25
#> 66        31 7e 56 12 7f be 04 37 00 97 ce 34 70 87 b2 33
#> 82        bf 72 2b 64 07 2b eb 44 86 bd a4 03 1d 27 24 4f
```

Tag 18 marks a COSE_Sign1. Its four parts are the protected header, a
byte string holding the encoded map
[`{}`](https://rdrr.io/r/base/Paren.html) (`a0`); the unprotected
header, the algorithm (1: -7, ES256) and a key ID (4: `"11"`); the
payload; and the 64-byte signature, in rows of 16.

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

## Tags of your own

zucbor converts a handful of tags; the rest come back as `cbor_tag`. Two
hooks give any other tag a meaning in R, without zucbor knowing about
it: `tag_handlers` when decoding, and an
[`as_cbor()`](https://pedrobtz.github.io/zucbor/reference/as_cbor.md)
method when encoding. Together they make a class of your own round-trip.
Handlers run only after the whole input has passed its checks, so they
never see malformed bytes.

### UUIDs (tag 37)

RFC 9562 UUIDs travel as tag 37 around their 16 bytes. Here they become
a small class holding the usual text form:

``` r

uuid <- function(text) structure(tolower(text), class = "uuid")
format.uuid <- function(x, ...) unclass(x)
print.uuid <- function(x, ...) print(paste0("<uuid ", format(x), ">"), quote = FALSE)

as_cbor.uuid <- function(x, ...) {
  h <- gsub("-", "", unclass(x))
  cbor_tag(37, as.raw(strtoi(substring(h, seq(1, 31, 2), seq(2, 32, 2)), 16L)))
}
uuid_from_bytes <- function(bytes) {
  # The content is checked CBOR, but not checked to be a UUID: that is ours.
  if (!is.raw(bytes) || length(bytes) != 16L) stop("a UUID is 16 bytes")
  h <- paste(sprintf("%02x", as.integer(bytes)), collapse = "")
  uuid(paste(substring(h, c(1, 9, 13, 17, 21), c(8, 12, 16, 20, 32)), collapse = "-"))
}

id <- uuid("F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6")
bytes <- cbor_encode(list(id = id, n = 1L))
cbor_diagnose(bytes)
#> [1] "{\"n\": 1, \"id\": 37(h'f81d4fae7dec11d0a76500a0c91e6bf6')}"

cbor_decode(bytes, tag_handlers = list("37" = uuid_from_bytes))
#> $n
#> [1] 1
#> 
#> $id
#> [1] <uuid f81d4fae-7dec-11d0-a765-00a0c91e6bf6>
```

A method defined in a script is found from the global environment. A
package registers it instead, with `S3method(zucbor::as_cbor, uuid)` in
its `NAMESPACE` (roxygen: `@exportS3Method zucbor::as_cbor`).

### IP addresses (tags 52 and 54)

RFC 9164 writes an IPv4 address as tag 52 around 4 bytes and an IPv6
address as tag 54 around 16, and a prefix as an array of its length and
the address bytes with trailing zero bytes left out. Decoding them to
text takes two handlers:

``` r

ip_text <- function(v, width) {
  prefix <- NULL
  if (is.list(v)) {                              # [length, bytes]: a prefix
    prefix <- v[[1]]
    v <- v[[2]]
  }
  b <- as.integer(c(v, raw(width - length(v))))  # put back the zero bytes
  addr <- if (width == 4) {
    paste(b, collapse = ".")
  } else {
    paste(sprintf("%x", b[c(TRUE, FALSE)] * 256L + b[c(FALSE, TRUE)]), collapse = ":")
  }
  if (is.null(prefix)) addr else paste0(addr, "/", prefix)
}
ip <- list("52" = function(v) ip_text(v, 4), "54" = function(v) ip_text(v, 16))

cbor_decode(hex("d8 34 44 c0 00 02 01"), tag_handlers = ip)            # 192.0.2.1
#> [1] "192.0.2.1"
cbor_decode(hex("d8 34 82 18 18 43 c0 00 02"), tag_handlers = ip)      # 192.0.2.0/24
#> [1] "192.0.2.0/24"
cbor_decode(hex("d8 36 50 20 01 0d b8 12 34 de ed be ef ca fe fa ce fe ed"), tag_handlers = ip)
#> [1] "2001:db8:1234:deed:beef:cafe:face:feed"
```

### Decimal fractions (tag 4)

Tag 4 is `[exponent, mantissa]`, the value mantissa × 10^exponent, so
273.15 is `[-2, 27315]` exactly. The
[decimal](https://pedrobtz.github.io/decimal/) package holds such
numbers exactly in R, and stores each as its text, which makes both
directions a few lines of string handling. The mantissa may be wider
than 2^53;
[`cbor_bigint()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md)
writes it exactly either way.

``` r

as_cbor.decimal <- function(x, ...) {
  one <- function(s) {
    m <- regmatches(s, regexec("^(-?)([0-9]*)[.]?([0-9]*)(?:[eE]([-+]?[0-9]+))?$", s, perl = TRUE))[[1]]
    if (length(m) == 0L) stop("no CBOR form for decimal ", s)
    digits <- sub("^0+(?=.)", "", paste0(m[3], m[4]), perl = TRUE)
    exponent <- (if (nzchar(m[5])) as.integer(m[5]) else 0L) - nchar(m[4])
    cbor_tag(4, list(exponent, cbor_bigint(paste0(if (digits != "0") m[2], digits))))
  }
  s <- as.character(x)
  if (length(s) == 1L) one(s) else lapply(s, one)
}
decimal_from_tag <- function(v) {
  digits <- if (inherits(v, "cbor_bigint")) as.character(v) else sprintf("%.0f", as.numeric(v))
  decimal::decimal(paste0(digits[2], "E", digits[1]))
}

price <- decimal::decimal("273.15")
bytes <- cbor_encode(price)
bytes
cbor_diagnose(bytes)
cbor_decode(bytes, tag_handlers = list("4" = decimal_from_tag))
```

### Errors in handlers

Validity of the CBOR is zucbor’s to check; what the content means is the
handler’s. A handler that fails, as `uuid_from_bytes()` does on two
bytes, raises `zucbor_handler_error`, which carries the tag number and
the handler’s own error:

``` r

e <- tryCatch(
  cbor_decode(hex("d8 25 42 01 02"), tag_handlers = list("37" = uuid_from_bytes)),
  zucbor_handler_error = function(e) e
)
e$tag
#> [1] 37
conditionMessage(e$parent)
#> [1] "a UUID is 16 bytes"
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
refuses it,
[`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
reads both items, and
[`cbor_decode_prefix()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode_prefix.md)
reads the first and says where it ended:

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
cbor_decode_prefix(inner)$consumed
#> [1] 4
```

When the embedded item is meant to be decoded, a handler for tag 24 does
it in place. It is still an explicit call, so it can set limits of its
own:

``` r

cbor_decode(hex("d8 18 44 82 01 61 61"),
            tag_handlers = list("24" = function(b) cbor_decode(b, max_depth = 4)))
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
```

## Telemetry as a data frame

Sensor data often arrives as an array of records with text keys. SenML
(RFC 8428) is the standard shape: each record carries a name, a value
and a time, and the first may carry a base name and base time for the
rest. `data_frame = TRUE` makes such an array a data frame, one row per
record:

``` r

pack <- list(
  list(bn = "urn:dev:ow:10e2073a01080063:", bt = 1320067464, n = "voltage", u = "V", v = 120.1),
  list(n = "current", t = -5L, u = "A", v = 1.2),
  list(n = "current", t = -4L, u = "A", v = 1.3)
)
bytes <- cbor_encode(pack)
senml <- cbor_decode(bytes, data_frame = TRUE)
senml
#>         n u     v                           bn         bt  t
#> 1 voltage V 120.1 urn:dev:ow:10e2073a01080063: 1320067464 NA
#> 2 current A   1.2                         <NA>         NA -5
#> 3 current A   1.3                         <NA>         NA -4
```

The columns are every key any record has, in the order they are first
seen, and a record without a key has `NA` there. Each column simplifies
as an array would, so `v` is numeric and `n` is text. With the base
values filled in, the times are absolute:

``` r

senml$name <- paste0(senml$bn[1], senml$n)
as.POSIXct(senml$bt[1] + ifelse(is.na(senml$t), 0, senml$t), tz = "UTC")
#> [1] "2011-10-31 13:24:24 UTC" "2011-10-31 13:24:19 UTC"
#> [3] "2011-10-31 13:24:20 UTC"
```

The columns come back as `n`, `u`, `v`, `bn`, `bt`, then `t`, which only
the later records have: deterministic encoding writes each map’s keys
sorted by their encoded bytes, shorter keys first, and decoding keeps
the order it first reads them in. Select columns by name when order
matters.

A data frame encodes the same way, one map per row, so frames
round-trip, apart from row names, factor levels and column order:

``` r

df <- data.frame(sensor = c("t0", "t1"), c = c(20.25, 20.5), ok = c(TRUE, NA))
cbor_diagnose(cbor_encode(df))
#> [1] "[{\"c\": 20.25, \"ok\": true, \"sensor\": \"t0\"}, {\"c\": 20.5, \"ok\": null, \"sensor\": \"t1\"}]"
cbor_decode(cbor_encode(df), data_frame = TRUE)
#>       c   ok sensor
#> 1 20.25 TRUE     t0
#> 2 20.50   NA     t1
```

Records that share no keys would make a frame with as many columns as
rows, so `max_cells` (ten million by default) bounds the cells of any
one frame, and is checked before the frame is built.

## Numeric data as typed arrays

RFC 8746 writes a numeric vector as one byte string instead of one item
per element. zucbor always decodes such typed arrays, and writes them
when asked, along with matrices as tag 1040:

``` r

m <- matrix(c(1.5, NA, -0, Inf), 2)
bytes <- cbor_encode(m, typed_arrays = TRUE)
cbor_diagnose(bytes)
#> [1] "1040([[2, 2], 86(h'000000000000f83fa20700000000f07f0000000000000080000000000000f07f')])"
identical(cbor_decode(bytes), m)
#> [1] TRUE
```

Every bit survives, `NA` and `-0` included. For large data it is smaller
and much faster in both directions:

``` r

x <- runif(1e5)
c(array = length(cbor_encode(x)), typed = length(cbor_encode(x, typed_arrays = TRUE)))
#>  array  typed 
#> 892249 800007
```

It is off by default because many CBOR decoders do not implement RFC
8746; use it when you know the reader does.

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

A long log of records, written as an RFC 8742 sequence, can be read one
record at a time in memory bounded by the largest record. Each is
checked whole, decoded and passed to `each` as soon as its last byte is
read, and the limits apply to each record rather than the whole file:

``` r

path <- tempfile(fileext = ".cbor")
writeBin(cbor_encode_seq(lapply(1:1000, function(i) list(i = i, v = i / 8))), path)
total <- 0
cbor_read_seq(path, each = function(r) total <<- total + r$v, max_size = 64)
#> [1] 1000
total
#> [1] 62562.5
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
