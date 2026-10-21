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

cbor_read_seq(file, ..., each = NULL, max_size = 64 * 1024^2)
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

  The largest input, in bytes, read before giving up with
  `zucbor_size_limit`; with `each`, the largest item.

- each:

  `NULL`, or a function of one argument, called with each item of the
  sequence in turn. See "Reading a sequence item by item".

## Value

As
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
or
[`cbor_decode_seq()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md);
with `each`, the number of items read, a double.

## Reading a sequence item by item

With `each`, `cbor_read_seq()` reads a sequence of any length in memory
bounded by its largest item: each item is decoded and passed to `each`
as soon as its last byte has been read, nothing is kept, and the call
returns the number of items read. A long telemetry log or a socket that
stays open is read this way.

Each item is still checked whole before anything is built from it, as
[`cbor_decode()`](https://pedrobtz.github.io/zucbor/reference/cbor_decode.md)
does, and the limits then apply to each item: `max_size` bounds the
bytes of one item, and `max_items` the data items inside one. A faulty
item stops the read with its condition, after `each` has been called for
every item before it; the condition's `offset` counts from the start of
the read, not of the item. So does input that ends inside an item. An
error in `each` propagates unchanged and stops the read too.

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

# A sequence of three items, one at a time.
writeBin(cbor_encode_seq(list(1L, "two", list(3L))), path)
cbor_read_seq(path, each = function(item) str(item))
#>  int 1
#>  chr "two"
#>  'AsIs' int 3
#> [1] 3
unlink(path)
```
