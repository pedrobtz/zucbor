# Getting started with zucbor

``` r

library(zucbor)
```

## A round trip

``` r

x <- list(name = "sensor-7", reading = c(21.5, 21.75), ok = TRUE,
          seen = as.POSIXct("2026-09-30 12:00:00", tz = "UTC"))
b <- cbor_encode(x)
length(b)
#> [1] 45
cbor_diagnose(b)
#> [1] "{\"ok\": true, \"name\": \"sensor-7\", \"seen\": 1(1790769600), \"reading\": [21.5, 21.75]}"
str(cbor_decode(b))
#> List of 4
#>  $ ok     : logi TRUE
#>  $ name   : chr "sensor-7"
#>  $ seen   : POSIXct[1:1], format: "2026-09-30 12:00:00"
#>  $ reading: num [1:2] 21.5 21.8
```

## How CBOR becomes R

| CBOR | R |
|----|----|
| integer | `integer`, `double` up to 2^53, `cbor_bigint` beyond |
| float | `double` |
| `true`, `false` | `logical` |
| `null`, `undefined` | `NULL`, or `NA` in a vector |
| byte string | `raw` |
| text string | `character` |
| array | an atomic vector when the elements agree, else a `list` |
| map with text keys | a named `list` |
| any other map | `cbor_map` |
| date and time tags | `POSIXct`, `Date` |
| other tags | `cbor_tag` |

``` r

cbor_decode(cbor_encode(list(1L, "a")))           # mixed: a list
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
cbor_decode(as.raw(c(0x82, 0x01, 0x02)))          # [1, 2]: an integer vector
#> [1] 1 2
cbor_decode(as.raw(c(0x81, 0x01)))                # [1]: I(1L), so it re-encodes as [1]
#> [1] 1
cbor_decode(as.raw(c(0x1b, rep(0xff, 8))))        # 2^64 - 1, exactly
#> <cbor_bigint[1]>
#> [1] 18446744073709551615
```

## Values R has no type for

``` r

cbor_encode(cbor_map(list(1L, -1L), list("a", "b")))    # integer keys
#> [1] a2 01 61 61 20 61 62
cbor_encode(cbor_tag(32, "https://example.com"))         # a URI tag
#>  [1] d8 20 73 68 74 74 70 73 3a 2f 2f 65 78 61 6d 70 6c 65 2e 63 6f 6d
cbor_encode(cbor_bigint("340282366920938463463374607431768211456"))   # 2^128
#>  [1] c2 51 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## Sequences

An RFC 8742 CBOR sequence is items one after another, as sensors stream
them:

``` r

s <- cbor_encode_seq(list(1, "two", list(three = 3)))
cbor_decode_seq(s)
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "two"
#> 
#> [[3]]
#> [[3]]$three
#> [1] 3
```
