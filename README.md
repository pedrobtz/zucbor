# zucbor

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zucbor/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zucbor/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zucbor/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zucbor/actions/workflows/coverage.yaml)
<!-- badges: end -->

zucbor encodes and decodes CBOR (RFC 8949), the binary counterpart of
JSON, to and from ordinary R vectors and lists. It is built for input you
do not trust — COSE and CWT tokens, WebAuthn passkey data, CoAP device
telemetry — and for output that must be byte-exact.

- **Decoding checks the whole input before building anything.** Well-formedness,
  UTF-8, tag content, duplicate map keys and configurable depth, size and item
  limits are all enforced first, so a length header can never make R allocate
  for data the input does not contain.
- **Encoding is deterministic.** Identical R objects give identical bytes on
  every platform (RFC 8949 core deterministic encoding), and decoding then
  re-encoding deterministic input gives back exactly the same bytes — what a
  signature over CBOR needs.
- **Values keep their meaning.** Integers stay exact beyond 2^53, byte strings
  stay raw, maps with integer keys stay maps, dates become `POSIXct` and `Date`.
- **No system library.** A subset of [TinyCBOR](https://github.com/intel/tinycbor)
  is bundled; the encoder and the diagnostic printer are zucbor's own.

## Installation

``` r
install.packages("zucbor")

# or the development version:
# install.packages("pak")
pak::pak("pedrobtz/zucbor")
```

Building from source needs a C compiler; with GCC, version 11 or newer
(older GCC rejects a construct in the bundled TinyCBOR 7.0).

## Decoding

``` r
library(zucbor)

cbor_decode(as.raw(c(0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03)))
#> $a
#> [1] 1
#>
#> $b
#> [1] 2 3
```

A map whose keys are not all text — a COSE header, say — is a `cbor_map`,
never a list with the keys quietly turned into names:

``` r
cbor_decode(as.raw(c(0xa2, 0x01, 0x26, 0x04, 0x42, 0x31, 0x31)))
#> <cbor_map: 2 entries>
#> [[1]]
#> [1] -7
#> [[4]]
#> [1] 31 31
```

Hostile input fails with a classed condition, before any R object exists:

``` r
# An array header claiming 2^64 - 1 elements, in nine bytes.
tryCatch(cbor_decode(as.raw(c(0x9b, rep(0xff, 8)))),
         zucbor_error = function(e) class(e)[1])
#> [1] "zucbor_parse_error"

# The same key twice, once in a longer encoding: refused by value.
cbor_validate(as.raw(c(0xa2, 0x01, 0x00, 0x18, 0x01, 0x00)))
#> [1] FALSE
```

## Encoding

``` r
b <- cbor_encode(list(alg = -7, kid = charToRaw("11"),
                      when = as.POSIXct("2026-01-01", tz = "UTC")))
b
#>  [1] a3 63 61 6c 67 26 63 6b 69 64 42 31 31 64 77 68 65 6e c1 1a 69 55 b9 00

cbor_diagnose(b)
#> [1] "{\"alg\": -7, \"kid\": h'3131', \"when\": 1(1767225600)}"

# Deterministic: map entries are sorted by their encoded keys.
identical(cbor_encode(list(b = 1, a = 2)), cbor_encode(list(a = 2, b = 1)))
#> [1] TRUE
```

`-7` is a double in R, but it is written as the integer a COSE algorithm
identifier must be: a whole double is always an integer in CBOR.

## What zucbor is not

It decodes and encodes CBOR. It does not verify COSE signatures, validate
against CDDL schemas, or decode base64: those belong to other packages.

## Learn more

- `vignette("untrusted", package = "zucbor")`: limits, duplicate keys and
  deterministic input.
- `vignette("cose-webauthn", package = "zucbor")`: WebAuthn attestation
  objects, COSE keys and signed structures.
- [Examples](https://pedrobtz.github.io/zucbor/articles/examples.html): worked
  examples for COSE keys, wide integers, dates, embedded CBOR, telemetry,
  files and limits.
- `?cbor_decode` and `?cbor_encode` state the full mapping between CBOR and R.

zucbor is one of the `zu*` packages, with
[zujson](https://github.com/pedrobtz/zujson),
[zuyaml](https://github.com/pedrobtz/zuyaml) and
[zuxml](https://github.com/pedrobtz/zuxml).
