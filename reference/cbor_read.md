# Read CBOR from a file or connection

Reads the input and decodes it as
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
or
[`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
would. At most `max_size + 1` bytes are ever read, so an oversized file
or an endless connection fails with `zucbor_size_limit` rather than
exhausting memory.

## Usage

``` r
cbor_read(file, ..., max_size = 64 * 1024^2)

cbor_read_seq(file, ..., max_size = 64 * 1024^2)
```

## Arguments

- file:

  A file path, a URL, or a connection.

- ...:

  Arguments passed on to
  [`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
  or
  [`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md).

- max_size:

  Largest input allowed, in bytes, or `Inf`.

## Value

As
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
or
[`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md).

## Details

A string with an `http`, `https`, `ftp`, `ftps` or `file` scheme is read
with [`url()`](https://rdrr.io/r/base/connections.html), any other
string as a file path. A connection that is not open is opened in `"rb"`
mode and closed afterwards; an open one must be binary, is read from its
current position, and is left open.

## Examples

``` r
path <- tempfile(fileext = ".cbor")
writeBin(as.raw(c(0xa1, 0x61, 0x61, 0x01)), path)
cbor_read(path)
#> $a
#> [1] 1
#> 
unlink(path)
```
