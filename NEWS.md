# zucbor 0.0.0.9000

* Package skeleton: metadata, licence and build configuration.
* Bundles TinyCBOR 7.0 (`src/vendor/tinycbor`), verified byte-for-byte
  against the upstream release by `tools/verify-vendor`.
* `zucbor_info()` reports the bundled TinyCBOR version, the ceiling on
  nesting depth and the default decoding limits.
* `cbor_validate()` checks that a raw vector holds well-formed, valid CBOR,
  or an RFC 8742 sequence, within depth, size and item limits, without
  building any R value. Duplicate map keys are refused by default, compared
  by value. `deterministic = TRUE` also requires RFC 8949 core deterministic
  encoding. Every fault is a classed condition inheriting `zucbor_error`
  (see `?"zucbor-conditions"`).
* `cbor_decode()` and `cbor_decode_seq()` turn CBOR into ordinary R values,
  after the same whole-input check `cbor_validate()` runs. Arrays simplify to
  atomic vectors when their elements agree; maps with text keys become named
  lists; integers stay exact (`cbor_bigint` beyond 2^53); dates and times
  become `POSIXct` and `Date`. `cbor_read()` and `cbor_read_seq()` read from
  a file, URL or connection, never more than `max_size + 1` bytes.
* `cbor_map()`, `cbor_tag()`, `cbor_simple()` and `cbor_bigint()` represent
  the values R has no native type for.
* `cbor_encode()` and `cbor_encode_seq()` write R values as CBOR in RFC 8949
  core deterministic encoding: identical R objects give identical bytes on
  every platform. Whole doubles are written as integers, so a COSE
  algorithm identifier written as `-7` stays an integer.
* Decoding marks a one-element array with `I()` and keeps booleans apart
  from numbers, so that decoding and re-encoding gives back the same bytes.
* `cbor_diagnose()` shows CBOR in RFC 8949 diagnostic notation, as the RFC's
  own examples write it, after the same check as `cbor_validate()`.

