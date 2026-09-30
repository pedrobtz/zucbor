# Changelog

## zucbor 0.0.0.9000

- Package skeleton: metadata, licence and build configuration.
- Bundles TinyCBOR 7.0 (`src/vendor/tinycbor`), verified byte-for-byte
  against the upstream release by `tools/verify-vendor`.
- [`zucbor_info()`](https://pedrobtz.github.io/zucbor/reference/zucbor_info.md)
  reports the bundled TinyCBOR version, the ceiling on nesting depth and
  the default decoding limits.
- [`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
  checks that a raw vector holds well-formed, valid CBOR, or an RFC 8742
  sequence, within depth, size and item limits, without building any R
  value. Duplicate map keys are refused by default, compared by value.
  `deterministic = TRUE` also requires RFC 8949 core deterministic
  encoding. Every fault is a classed condition inheriting `zucbor_error`
  (see
  [`?"zucbor-conditions"`](https://pedrobtz.github.io/zucbor/reference/zucbor-conditions.md)).
- [`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
  and
  [`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
  turn CBOR into ordinary R values, after the same whole-input check
  [`cbor_validate()`](https://pedrobtz.github.io/zucbor/reference/cbor_validate.md)
  runs. Arrays simplify to atomic vectors when their elements agree;
  maps with text keys become named lists; integers stay exact
  (`cbor_bigint` beyond 2^53); dates and times become `POSIXct` and
  `Date`.
  [`cbor_read()`](https://pedrobtz.github.io/zucbor/reference/cbor_read.md)
  and
  [`cbor_read_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_read.md)
  read from a file, URL or connection, never more than `max_size + 1`
  bytes.
- [`cbor_map()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md),
  [`cbor_tag()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md),
  [`cbor_simple()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md)
  and
  [`cbor_bigint()`](https://pedrobtz.github.io/zucbor/reference/cbor-values.md)
  represent the values R has no native type for.
