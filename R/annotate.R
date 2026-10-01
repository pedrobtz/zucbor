#' Annotated hex dump of CBOR
#'
#' Shows where each byte of CBOR goes: one line per head, with its offset,
#' its bytes in hex, indented by nesting, and what it is. A string's content
#' follows its head, 16 bytes a line, and the first of those lines previews
#' it. Every byte of the input appears exactly once in the hex column. This
#' is the view needed to review a signed message byte by byte;
#' [cbor_diagnose()] shows what the message means instead.
#'
#' The input is checked first, exactly as [cbor_validate()] checks it. The
#' output is bounded by a constant multiple of the input's size: previews
#' stop at 32 bytes and indentation at 16 levels.
#'
#' Offsets are 0-based, in decimal, as in zucbor's error conditions.
#' Integers show their value (`negative(-501)`), floats their width and
#' value (`float16 1.5`), and indefinite-length items `(*)` and a `break`.
#'
#' @inheritParams cbor_diagnose
#' @return A character vector of class `cbor_annotation`, one element per
#'   line, which prints as the lines.
#' @seealso [cbor_diagnose()] for diagnostic notation.
#' @export
#' @examples
#' cbor_annotate(as.raw(c(0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03)))
#'
#' # A COSE_Sign1 message's protected header, {1: -7}, inside a byte string.
#' cbor_annotate(cbor_encode(list(cbor_encode(cbor_map(list(1L), list(-7))), "payload")))
cbor_annotate <- function(x, sequence = FALSE, deterministic = FALSE,
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
  res <- .Call(zucbor_annotate, x, opts, as.numeric(max_items))
  if (!is.null(res[[1L]])) zu_raise_fault(res[[1L]], call)
  p <- res[[2L]]
  if (length(p$offset) == 0L) return(structure(character(), class = "cbor_annotation"))
  offset <- format(p$offset, scientific = FALSE, width = nchar(format(max(p$offset), scientific = FALSE)))
  hex <- formatC(p$hex, width = -max(nchar(p$hex)), flag = "-")
  lines <- paste0(offset, "  ", hex, "  ", ifelse(nzchar(p$desc), paste0("# ", p$desc), ""))
  structure(sub(" +$", "", lines), class = "cbor_annotation")
}

#' @export
print.cbor_annotation <- function(x, ...) {
  if (length(x)) cat(unclass(x), sep = "\n") else cat("<empty cbor_annotation>\n")
  invisible(x)
}

#' @export
format.cbor_annotation <- function(x, ...) {
  unclass(x)
}
