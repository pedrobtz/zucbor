# zucbor 0.1.0

* Initial CRAN release.
* `cbor_decode()`, `cbor_decode_seq()`, `cbor_read()` and `cbor_read_seq()`
  turn CBOR (RFC 8949) and CBOR sequences (RFC 8742) into ordinary R values.
  The whole input is checked first -- well-formedness, UTF-8, tag content,
  duplicate map keys (by value), and depth, size and item limits -- so a
  length header can never make R allocate for data the input does not hold.
  Every fault is a classed condition inheriting `zucbor_error`.
* `cbor_encode()` and `cbor_encode_seq()` write RFC 8949 core deterministic
  encoding: identical R objects give identical bytes on every platform, and
  decoding then re-encoding deterministic input reproduces it exactly.
* `cbor_annotate()` prints an annotated hex dump: each head with its offset,
  bytes and meaning, for reviewing a signed message byte by byte.
* `cbor_decode_prefix()` decodes the item a raw vector starts with and
  reports how many bytes it used, for CBOR inside binary framing such as
  WebAuthn `authData`. What follows the item is not read.
* RFC 8746 typed arrays decode to integer and double vectors, and
  multi-dimensional arrays (tags 40 and 1040) to matrices and arrays.
  `cbor_encode(typed_arrays = TRUE)` writes numeric vectors as typed arrays
  and matrices as tag 1040: smaller, and much faster to read and write.
  Off by default, so existing output is unchanged.
* Data frames encode as an array of one map per row, keyed by column name,
  and `data_frame = TRUE` in the decoders reads such an array (SenML, for
  instance) back as a data frame. `max_cells` bounds the cells of a decoded
  frame before it is built.
* `cbor_read_seq(each =)` reads a sequence of any length in memory bounded
  by its largest item: each item is checked whole, decoded and passed to a
  function as soon as its last byte arrives. The limits then apply per item.
* `tag_handlers =` in the decoders gives meaning to any tag: a function per
  tag number turns its decoded content into an R value. Handlers run only
  after the whole input has been checked, and an error in one is
  `zucbor_handler_error`. `as_cbor()` is the encoding half: an S3 generic
  that `cbor_encode()` calls for any class it does not know.
* `cbor_validate()` runs the check alone; `cbor_diagnose()` shows CBOR in
  RFC 8949 diagnostic notation, as the RFC's own examples write it.
* `cbor_map()`, `cbor_tag()`, `cbor_simple()` and `cbor_bigint()` represent
  the values R has no native type for: maps with non-text keys, tagged
  items, simple values and integers beyond 2^53.
* Bundles the parser and validator of TinyCBOR 7.0; no system library is
  needed.
