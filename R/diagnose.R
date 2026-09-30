#' CBOR diagnostic notation
#'
#' Shows CBOR as RFC 8949 section 8 diagnostic notation: the human-readable
#' form CBOR specifications use for examples. The input is checked first,
#' exactly as [cbor_validate()] checks it, so nothing hostile reaches the
#' printer, and the output is bounded by the input's size.
#'
#' The notation matches RFC 8949's own Appendix A. Numbers print as JSON and
#' JavaScript print them, with `.0` added to a float that would otherwise
#' read as an integer (`1.0`, `1.0e+300`). Text is ASCII: characters beyond
#' it appear as `\u` escapes, as Appendix A writes them. An indefinite-length
#' item shows `_ ` after its opening bracket, and a chunked string its chunks
#' as `(_ "a", "b")`. A sequence's items are separated by commas (RFC 8742
#' section 4.2).
#'
#' @inheritParams cbor_validate
#' @return A single string.
#' @seealso [cbor_decode()] to turn CBOR into R values.
#' @export
#' @examples
#' cbor_diagnose(as.raw(c(0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03)))
#' cbor_diagnose(cbor_encode(list(when = Sys.Date(), pi = pi, bytes = as.raw(1:4))))
#' cbor_diagnose(as.raw(c(0x01, 0xf9, 0x3e, 0x00)), sequence = TRUE)
cbor_diagnose <- function(x, sequence = FALSE, deterministic = FALSE,
                          duplicate_keys = FALSE, max_depth = 256L,
                          max_size = 64 * 1024^2, max_items = 1e6) {
  call <- sys.call()
  zu_arg_raw(x, "x", call)
  zu_arg_flag(sequence, "sequence", call)
  zu_arg_flag(deterministic, "deterministic", call)
  zu_arg_flag(duplicate_keys, "duplicate_keys", call)
  zu_arg_limits(max_depth, max_size, max_items, call)
  if (length(x) > max_size) zu_raise_fault(zu_size_fault(max_size), call)
  opts <- as.integer(c(sequence, deterministic, duplicate_keys, max_depth))
  res <- .Call(zucbor_diagnose, x, opts, as.numeric(max_items))
  if (!is.null(res[[1L]])) zu_raise_fault(res[[1L]], call)
  res[[2L]]
}
