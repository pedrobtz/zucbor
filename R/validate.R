#' Validate CBOR
#'
#' Checks that `x` holds well-formed, valid CBOR within the given limits,
#' without building any R value. This is exactly the check `cbor_decode()`
#' runs before it builds anything, so the two agree about the bytes; they
#' disagree only where the bytes are valid but R cannot hold the value, such
#' as a text string containing U+0000.
#'
#' The check covers well-formedness (RFC 8949 section 3), UTF-8 in text
#' strings, the content type of the tags TinyCBOR knows, duplicate map keys
#' (compared by value, so `1` encoded in one byte and in two is the same key),
#' and the limits.
#'
#' @param x A raw vector.
#' @param sequence If `TRUE`, `x` is an RFC 8742 CBOR sequence of zero or
#'   more items; if `FALSE`, it must be exactly one item.
#' @param deterministic If `TRUE`, also require RFC 8949 section 4.2.1 core
#'   deterministic encoding: shortest integers, lengths and floats, definite
#'   lengths, map keys in bytewise order, and bignums in preferred form.
#' @param duplicate_keys If `FALSE` (the default), a map with the same key
#'   twice is invalid.
#' @param max_depth Deepest nesting allowed, counting arrays, maps and tags.
#'   At most `zucbor_info()$max_depth_cap`.
#' @param max_size Largest input allowed, in bytes, or `Inf`.
#' @param max_items Most data items allowed, counting every tag and every
#'   chunk of an indefinite-length string, or `Inf`.
#' @param error If `TRUE`, raise the classed condition describing the fault
#'   instead of returning `FALSE`; see [zucbor-conditions].
#' @return `TRUE` or `FALSE`; with `error = TRUE`, `TRUE` invisibly or an
#'   error.
#' @export
#' @examples
#' cbor_validate(as.raw(c(0x83, 0x01, 0x02, 0x03)))   # [1, 2, 3]
#' cbor_validate(as.raw(c(0x83, 0x01, 0x02)))         # truncated
#' cbor_validate(as.raw(c(0xa2, 0x01, 0x00, 0x01, 0x00)))  # {1: 0, 1: 0}
#' cbor_validate(as.raw(c(0x01, 0x02)), sequence = TRUE)
cbor_validate <- function(x, sequence = FALSE, deterministic = FALSE,
                          duplicate_keys = FALSE, max_depth = 256L,
                          max_size = 64 * 1024^2, max_items = 1e6,
                          error = FALSE) {
  call <- sys.call()
  zu_arg_flag(error, "error", call)
  fault <- zu_check_raw(x, sequence, deterministic, duplicate_keys,
                        max_depth, max_size, max_items, call)
  if (is.null(fault)) {
    if (error) invisible(TRUE) else TRUE
  } else {
    if (error) zu_raise_fault(fault, call) else FALSE
  }
}

# The check phase: argument checks, then the walk. Returns NULL or a fault;
# a size fault is returned as one too, so cbor_validate() can say FALSE.
zu_check_raw <- function(x, sequence, deterministic, duplicate_keys,
                         max_depth, max_size, max_items, call = NULL) {
  zu_arg_raw(x, "x", call)
  zu_arg_flag(sequence, "sequence", call)
  zu_arg_flag(deterministic, "deterministic", call)
  zu_arg_flag(duplicate_keys, "duplicate_keys", call)
  zu_arg_limits(max_depth, max_size, max_items, call)
  if (length(x) > max_size) {
    return(structure(list(
      status = "ZU_ERR_SIZE_LIMIT", detail = NA_character_, offset = NA_real_,
      limit = "max_size", limit_value = as.numeric(max_size)
    ), class = "zu_fault"))
  }
  .Call(zucbor_check, x, sequence, deterministic, duplicate_keys,
        as.integer(max_depth), as.numeric(max_items))
}
