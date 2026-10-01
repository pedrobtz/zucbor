#' Teach `cbor_encode()` a class
#'
#' [cbor_encode()] calls `as_cbor()` on every object whose class it does not
#' know, so a package or a script can say how its own class is written by
#' adding a method. A method returns something `cbor_encode()` does know,
#' typically a [cbor_tag()] holding a raw vector, a string or a number.
#' [cbor_decode()]'s `tag_handlers` argument is the other half: it turns the
#' tag back into the class.
#'
#' The default method returns `x` unchanged, and `cbor_encode()` then writes
#' it as its underlying type, as it does for any class without a method.
#'
#' `as_cbor()` is called only for a class `cbor_encode()` does not handle
#' itself: not for `POSIXct`, `Date`, `factor`, data frames, `POSIXlt` or
#' zucbor's own classes, nor for a value whose only class is `AsIs`. It is
#' called once per value: the result is written as it is, even if its class
#' is one `cbor_encode()` does not know, though each of its elements is
#' converted in turn. A result of the same class as `x`, other than `x`
#' itself, is refused with `zucbor_unsupported_type`, since it is most
#' likely a method that forgot to convert.
#'
#' Encoding stays deterministic only if the methods are: a method should
#' depend on nothing but `x`.
#'
#' @param x An object of a class [cbor_encode()] does not know.
#' @param ... For methods; `cbor_encode()` passes nothing.
#' @return A value [cbor_encode()] can write.
#' @seealso [cbor_decode()] for `tag_handlers`, and the examples article
#'   for recipes for UUIDs, IP addresses and decimal fractions.
#' @export
#' @examples
#' # RFC 9562 UUIDs as tag 37, from a class of our own.
#' uuid <- function(hex) structure(list(hex = hex), class = "my_uuid")
#' as_cbor.my_uuid <- function(x, ...) {
#'   h <- gsub("-", "", x$hex)
#'   bytes <- as.raw(strtoi(substring(h, seq(1, 31, 2), seq(2, 32, 2)), 16L))
#'   cbor_tag(37, bytes)
#' }
#' # Methods defined in a script are found from the global environment;
#' # a package registers them with S3method(zucbor::as_cbor, my_uuid).
#' id <- uuid("f81d4fae-7dec-11d0-a765-00a0c91e6bf6")
#' bytes <- cbor_encode(list(id = id))
#' cbor_diagnose(bytes)
#'
#' back <- cbor_decode(bytes, tag_handlers = list("37" = function(value) {
#'   h <- paste(format(as.hexmode(as.integer(value)), width = 2), collapse = "")
#'   uuid(paste(substring(h, c(1, 9, 13, 17, 21), c(8, 12, 16, 20, 32)), collapse = "-"))
#' }))
#' identical(back$id, id)
as_cbor <- function(x, ...) {
  UseMethod("as_cbor")
}

#' @rdname as_cbor
#' @export
as_cbor.default <- function(x, ...) {
  x
}
