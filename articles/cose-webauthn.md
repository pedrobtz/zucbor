# COSE and WebAuthn

COSE (RFC 9052), CWT (RFC 8392) and WebAuthn all carry their data as
CBOR. This vignette takes structures from their specifications apart
with zucbor. It stops where cryptography starts: zucbor gives you the
exact bytes to verify, and another package verifies them.

``` r

library(zucbor)
hex <- function(h) as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
```

## A WebAuthn attestation object

When a passkey is created, the authenticator returns an *attestation
object*. This one is the WebAuthn Level 3 test vector “ES256 Credential
with No Attestation”:

``` r

att <- hex(paste0(
  "a363666d74646e6f6e656761747453746d74a068617574684461746158a4bfabc374",
  "32958b063360d3ad6461c9c4735ae7f8edd46592a5e0f01452b2e4b5590000000084",
  "46ccb9ab1db374750b2367ff6f3a1f0020f91f391db4c9b2fde0ea70189cba3fb63f",
  "579ba6122b33ad94ff3ec330084be4a5010203262001215820afefa16f97ca9b2d23",
  "eb86ccb64098d20db90856062eb249c33a9b672f26df61225820930a56b87a2fca66",
  "334b03458abf879717c12cc68ed73290af2e2664796b9220"))
ao <- cbor_decode(att)
str(ao)
#> List of 3
#>  $ fmt     : chr "none"
#>  $ attStmt : Named list()
#>  $ authData: raw [1:164] bf ab c3 74 ...
```

`authData` is a byte string with its own binary layout: a 32-byte hash
of the relying party’s ID, a flags byte, a 4-byte counter, a 16-byte
AAGUID, a 2-byte credential ID length and the ID, then the credential’s
public key as a COSE_Key, which is CBOR again.

``` r

ad <- ao$authData
id_len <- as.integer(ad[54]) * 256L + as.integer(ad[55])
key <- cbor_decode(ad[(56 + id_len):length(ad)])
key
#> <cbor_map: 5 entries>
#> [[1]]
#> [1] 2
#> [[3]]
#> [1] -7
#> [[-1]]
#> [1] 1
#> [[-2]]
#>  [1] af ef a1 6f 97 ca 9b 2d 23 eb 86 cc b6 40 98 d2 0d b9 08 56 06 2e b2 49 c3
#> [26] 3a 9b 67 2f 26 df 61
#> [[-3]]
#>  [1] 93 0a 56 b8 7a 2f ca 66 33 4b 03 45 8a bf 87 97 17 c1 2c c6 8e d7 32 90 af
#> [26] 2e 26 64 79 6b 92 20
```

A COSE_Key uses integer map keys, so it is a `cbor_map`. Key 1 is the
key type (2, EC2), 3 the algorithm (-7, ES256), -1 the curve (1, P-256),
and -2 and -3 the coordinates.
[`cbor_diagnose()`](https://pedrobtz.github.io/zucbor/reference/cbor_diagnose.md)
shows the same thing the way the specifications write it:

``` r

cbor_diagnose(ad[(56 + id_len):length(ad)])
#> [1] "{1: 2, 3: -7, -1: 1, -2: h'afefa16f97ca9b2d23eb86ccb64098d20db90856062eb249c33a9b672f26df61', -3: h'930a56b87a2fca66334b03458abf879717c12cc68ed73290af2e2664796b9220'}"
```

If the authenticator had included extensions, they would follow the key
as a second CBOR item;
[`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
reads both.

## Re-encoding what was signed

Signature checks run over exact bytes. zucbor’s encoder is
deterministic, and decoding then re-encoding deterministic input
reproduces it exactly, so a structure can be taken apart, inspected and
put back:

``` r

identical(cbor_encode(ao), att)
#> [1] TRUE
```

That holds because one-element arrays decode as
[`I()`](https://rdrr.io/r/base/AsIs.html) values and re-encode as
arrays, booleans never turn into numbers, and whole numbers stay
integers. Across all 651 messages and signed structures in the COSE
working group’s examples, every one in deterministic form survives the
round trip byte for byte.

## A signed CWT

A CBOR Web Token is a COSE_Sign1 message, tag 18, whose payload is a map
of claims. This is RFC 8392’s example:

``` r

cwt <- hex(paste0(
  "d28443a10126a104524173796d6d657472696345434453413235365850a70175636f",
  "61703a2f2f61732e6578616d706c652e636f6d02656572696b77037818636f61703a",
  "2f2f6c696768742e6578616d706c652e636f6d041a5612aeb0051a5610d9f0061a56",
  "10d9f007420b7158405427c1ff28d23fbad1f29c4c7c6a555e601d6fa29f9179bc3d",
  "7438bacaca5acd08c8d4d4f96131680c429a01f85951ecee743a52b9b63632c57209",
  "120e1c9e30"))
msg <- cbor_decode(cwt)
msg$tag
#> [1] 18
str(msg$value, max.level = 1)
#> List of 4
#>  $ : raw [1:3] a1 01 26
#>  $ :Class 'cbor_map'  hidden list of 2
#>  $ : raw [1:80] a7 01 75 63 ...
#>  $ : raw [1:64] 54 27 c1 ff ...
```

The protected header and the payload are byte strings holding more CBOR.
Decoding them is explicit, so each gets the same checks and limits:

``` r

cbor_decode(msg$value[[1]])        # protected header: {1: -7}, ES256
#> <cbor_map: 1 entry>
#> [[1]]
#> [1] -7
claims <- cbor_decode(msg$value[[3]])
claims
#> <cbor_map: 7 entries>
#> [[1]]
#> [1] "coap://as.example.com"
#> [[2]]
#> [1] "erikw"
#> [[3]]
#> [1] "coap://light.example.com"
#> [[4]]
#> [1] 1444064944
#> [[5]]
#> [1] 1443944944
#> [[6]]
#> [1] 1443944944
#> [[7]]
#> [1] 0b 71
```

To verify the signature, a verifier builds the `Sig_structure` of RFC
9052 section 4.4 and checks the signature over its bytes. With zucbor
that is one call, and the bytes are exactly the ones the signer
produced, because the encoding is deterministic:

``` r

to_be_signed <- cbor_encode(list("Signature1", msg$value[[1]], raw(), msg$value[[3]]))
cbor_diagnose(to_be_signed)
#> [1] "[\"Signature1\", h'a10126', h'', h'a70175636f61703a2f2f61732e6578616d706c652e636f6d02656572696b77037818636f61703a2f2f6c696768742e6578616d706c652e636f6d041a5612aeb0051a5610d9f0061a5610d9f007420b71']"
```
