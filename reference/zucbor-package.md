# zucbor: Deterministic and Secure CBOR Encoding and Decoding

Encodes R values as Concise Binary Object Representation (CBOR, RFC
8949) and decodes CBOR into ordinary R vectors and lists. Decoding
checks the whole input against configurable depth, size and item limits
before any R object is built, so untrusted input from network peers and
devices cannot drive large allocations. Encoding is deterministic:
identical R objects always produce identical bytes.

## See also

Useful links:

- <https://github.com/pedrobtz/zucbor>

- <https://pedrobtz.github.io/zucbor/>

- Report bugs at <https://github.com/pedrobtz/zucbor/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]
