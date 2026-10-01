# Changelog

## zucbor 0.0.0.9000

- Initial CRAN release.
- [`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md),
  [`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md),
  [`cbor_read()`](https://pedrobtz.github.io/zucbor/reference/cbor_read.md)
  and
  [`cbor_read_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_read.md)
  turn CBOR (RFC 8949) and CBOR sequences (RFC 8742) into ordinary R
  values. The whole input is checked first – well-formedness, UTF-8, tag
  content, duplicate map keys (by value), and depth, size and item
  limits – so a length header can never make R allocate for data the
  input does not hold. Every fault is a classed condition inheriting
  `zucbor_error`.
- [`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
  and
  [`cbor_encode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
  write RFC 8949 core deterministic encoding: identical R objects give
  identical bytes on every platform, and decoding then re-encoding
  deterministic input reproduces it exactly.
- `tag_handlers =` in the decoders gives meaning to any tag: a function
  per tag number turns its decoded content into an R value. Handlers run
  only after the whole input has been checked, and an error in one is
  `zucbor_handler_error`.
  [`as_cbor()`](https://pedrobtz.github.io/zucbor/reference/as_cbor.md)
  is the encoding half: an S3 generic that
  [`cbor_encode()`](https://pedrobtz.github.io/zucbor/reference/cbor_encode.md)
  calls for any class it does not know.
- [`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
  runs the check alone;
  [`cbor_diagnose()`](https://pedrobtz.github.io/zucbor/reference/cbor_diagnose.md)
  shows CBOR in RFC 8949 diagnostic notation, as the RFC’s own examples
  write it.
- [`cbor_map()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md),
  [`cbor_tag()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md),
  [`cbor_simple()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md)
  and
  [`cbor_bigint()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md)
  represent the values R has no native type for: maps with non-text
  keys, tagged items, simple values and integers beyond 2^53.
- Bundles the parser and validator of TinyCBOR 7.0; no system library is
  needed.
