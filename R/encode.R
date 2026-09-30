#' Encode R values as CBOR
#'
#' Turns an R value into CBOR bytes. The encoding is always RFC 8949
#' section 4.2.1 core deterministic encoding, so identical R objects give
#' identical bytes on every platform: the shortest form of every integer,
#' length and tag number; definite lengths; the shortest float that holds
#' each value exactly; and map entries sorted by their encoded keys.
#'
#' @section R to CBOR:
#' | R | CBOR |
#' |---|---|
#' | `NULL`, `NA` of any type | `null` |
#' | `TRUE`, `FALSE` | `true`, `false` |
#' | `integer` | integer |
#' | `double`, whole, within CBOR's integer range, not `-0` | integer |
#' | any other `double`, including `NaN`, `Inf` and `-0` | float, shortest exact width |
#' | `character` | text string, UTF-8 |
#' | `raw` | one byte string, whatever its length |
#' | `factor` | its labels, as text |
#' | `POSIXct` | tag 1: whole seconds as an integer, else a float |
#' | `Date` | tag 1004 `"YYYY-MM-DD"`; tag 100 (days) outside years 0000-9999 |
#' | `cbor_bigint` | integer, or tag 2 or 3 beyond CBOR's integer range |
#' | `cbor_map`, `cbor_tag`, `cbor_simple` | a map, a tagged item, a simple value |
#' | unnamed list or vector | array |
#' | fully named list or vector | map with text keys |
#'
#' A length-one atomic vector is a single value, not an array, unless it is
#' wrapped in [I()] or `auto_unbox = FALSE`. A matrix is a flat array in
#' column-major order. A vector whose class zucbor does not know is written
#' as its underlying type.
#'
#' Whole doubles become integers because R has no integer literal: `-7`
#' written in R is a double, and as a CBOR float it would be a different
#' value from the integer a COSE algorithm identifier needs. So `1L` and `1`
#' encode identically.
#'
#' These have no CBOR form and raise `zucbor_unsupported_type`: complex
#' numbers, functions, environments, external pointers, S4 objects,
#' `POSIXlt` (convert with [as.POSIXct()]) and data frames. Names that are
#' partly missing, `NA` or empty are `zucbor_invalid_argument`, and two keys
#' that encode identically are `zucbor_duplicate_key`.
#'
#' @section Conversions that do not round-trip:
#' Decoding what `cbor_encode()` wrote gives back the value, except that:
#' `NA` comes back as `NULL`, or `NA` of the vector's type; a whole double
#' comes back as an integer; `list(1L)` and `1L` both encode as `1`;
#' `NaN` payloads are not kept; and fractional days of a `Date` are dropped.
#'
#' @param x An R value. For `cbor_encode_seq()`, a list whose elements are
#'   encoded one after another as an RFC 8742 CBOR sequence.
#' @param auto_unbox If `TRUE`, a length-one atomic vector is a single value;
#'   if `FALSE`, it is an array of one. Names used as map keys are always
#'   single text strings.
#' @param self_describe If `TRUE`, prefix each item with the self-describe
#'   tag 55799 (`d9 d9 f7`), which marks bytes as CBOR.
#' @param max_depth Deepest nesting to write, counting arrays, maps and tags
#'   as [cbor_decode()] does, so its output always decodes at the same
#'   `max_depth`.
#' @return A raw vector.
#' @seealso [cbor_decode()], [cbor-values].
#' @export
#' @examples
#' cbor_encode(list(a = 1, b = c(2, 3)))
#' cbor_encode(c(1.5, NaN, Inf))
#'
#' # A COSE header: integer keys need cbor_map().
#' cbor_encode(cbor_map(list(1L), list(-7)))
#'
#' # Deterministic: map entries are sorted by their encoded keys.
#' identical(cbor_encode(list(b = 1, a = 2)), cbor_encode(list(a = 2, b = 1)))
#'
#' cbor_encode_seq(list(1, "a", TRUE))
cbor_encode <- function(x, auto_unbox = TRUE, self_describe = FALSE,
                        max_depth = 256L) {
  zu_encode(x, sequence = FALSE, auto_unbox, self_describe, max_depth, sys.call())
}

#' @rdname cbor_encode
#' @export
cbor_encode_seq <- function(x, auto_unbox = TRUE, self_describe = FALSE,
                            max_depth = 256L) {
  call <- sys.call()
  if (!is.list(x) || is.object(x)) {
    zu_invalid_argument("x", "`x` must be a plain list: each element is one item of the sequence.", call)
  }
  zu_encode(x, sequence = TRUE, auto_unbox, self_describe, max_depth, call)
}

zu_encode <- function(x, sequence, auto_unbox, self_describe, max_depth, call) {
  zu_arg_flag(auto_unbox, "auto_unbox", call)
  zu_arg_flag(self_describe, "self_describe", call)
  zu_arg_limit(max_depth, "max_depth", zu_max_depth_cap(), allow_inf = FALSE, call)
  opts <- as.integer(c(sequence, auto_unbox, self_describe, max_depth))
  .Call(zucbor_encode, x, opts, call)
}
