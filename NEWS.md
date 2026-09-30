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
