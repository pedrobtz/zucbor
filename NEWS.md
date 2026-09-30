# zucbor 0.0.0.9000

* Package skeleton: metadata, licence and build configuration.
* Bundles TinyCBOR 7.0 (`src/vendor/tinycbor`), verified byte-for-byte
  against the upstream release by `tools/verify-vendor`.
* `zucbor_info()` reports the bundled TinyCBOR version, the ceiling on
  nesting depth and the default decoding limits.
