#' Read CBOR from a file or connection
#'
#' Reads the input and decodes it as [cbor_decode()] or [cbor_decode_seq()]
#' would. At most `max_size + 1` bytes are ever read, so an oversized file or
#' an endless connection fails with `zucbor_size_limit` rather than
#' exhausting memory.
#'
#' @section Reading a sequence item by item:
#' With `each`, `cbor_read_seq()` reads a sequence of any length in memory
#' bounded by its largest item: each item is decoded and passed to `each`
#' as soon as its last byte has been read, nothing is kept, and the call
#' returns the number of items read. A long telemetry log or a socket that
#' stays open is read this way.
#'
#' Each item is still checked whole before anything is built from it, as
#' [cbor_decode()] does, and the limits then apply to each item: `max_size`
#' bounds the bytes of one item, and `max_items` the data items inside one.
#' A faulty item stops the read with its condition, after `each` has been
#' called for every item before it; the condition's `offset` counts from the
#' start of the read, not of the item. So does input that ends inside an
#' item. An error in `each` propagates unchanged and stops the read too.
#'
#' A string with an `http`, `https`, `ftp`, `ftps` or `file` scheme is read
#' with [url()], any other string as a file path. A connection that is not
#' open is opened in `"rb"` mode and closed afterwards; an open one must be
#' binary, is read from its current position, and is left open.
#'
#' @param file A file path, a URL, or a connection.
#' @param ... Arguments passed on to [cbor_decode()] or [cbor_decode_seq()].
#' @param each `NULL`, or a function of one argument, called with each item
#'   of the sequence in turn. See "Reading a sequence item by item".
#' @param max_size The largest input, in bytes, read before giving up with
#'   `zucbor_size_limit`; with `each`, the largest item.
#' @return As [cbor_decode()] or [cbor_decode_seq()]; with `each`, the number
#'   of items read, a double.
#' @export
#' @examples
#' path <- tempfile(fileext = ".cbor")
#' writeBin(as.raw(c(0xa1, 0x61, 0x61, 0x01)), path)
#' cbor_read(path)
#'
#' # A sequence of three items, one at a time.
#' writeBin(cbor_encode_seq(list(1L, "two", list(3L))), path)
#' cbor_read_seq(path, each = function(item) str(item))
#' unlink(path)
cbor_read <- function(file, ..., max_size = 64 * 1024^2) {
  call <- sys.call()
  cbor_decode(zu_read_bounded(file, max_size, call), ..., max_size = max_size)
}

#' @rdname cbor_read
#' @export
cbor_read_seq <- function(file, ..., each = NULL, max_size = 64 * 1024^2) {
  call <- sys.call()
  if (!is.null(each)) return(zu_read_each(file, each, max_size, call, ...))
  cbor_decode_seq(zu_read_bounded(file, max_size, call), ..., max_size = max_size)
}

# cbor_read_seq(each =): roadmap Stage 15, design section 9. The buffer
# holds at most max_size bytes: the item being read, and whatever of the
# next items the last block brought. C checks and builds the complete items
# the buffer starts with (mode 3) and reports where the first incomplete one
# starts; that one waits for more input. The block size doubles with the
# incomplete item, so a large item costs linear time, not quadratic. Tests
# set a small `block` to feed items in pieces.
zu_read_each <- function(file, each, max_size, call, ..., block = 65536) {
  if (!is.function(each)) {
    zu_invalid_argument("each", "`each` must be NULL or a function.", call)
  }
  zu_arg_limit(max_size, "max_size", 2^53, allow_inf = TRUE, call)
  a <- zu_seq_args(call = call, ...)
  input <- zu_open_input(file, what = "file", prefix = "zucbor",
                         abort = function(arg, message) zu_invalid_argument(arg, message, call))
  if (input$close) on.exit(close(input$con), add = TRUE)
  raise <- function(fault, base) {
    fault$offset <- fault$offset + base
    zu_raise_fault(fault, call)
  }
  buf <- raw()
  base <- 0  # stream offset of buf[1]
  n <- 0
  repeat {
    room <- max_size - length(buf)
    if (room < 1) {
      # buf is one incomplete item already max_size long.
      f <- zu_size_fault(max_size)
      f$offset <- base
      zu_raise_fault(f, call)
    }
    want <- min(max(block, length(buf)), room)
    b <- tryCatch(readBin(input$con, "raw", n = want),
                  error = function(e) zu_abort("zucbor_io_error",
                    paste0("could not read input: ", conditionMessage(e)), call = call))
    if (length(b) == 0L) break
    buf <- if (length(buf)) c(buf, b) else b
    repeat {
      res <- .Call(zucbor_decode, buf, a$opts, a$max_items, call, a$handlers)
      if (!is.null(res[[1L]])) raise(res[[1L]], base)
      used <- res[[3L]]
      if (used == 0) break
      for (item in res[[2L]]) each(item)
      n <- n + length(res[[2L]])
      base <- base + used
      buf <- if (used == length(buf)) raw() else buf[-seq_len(used)]
      if (!length(buf)) break
    }
  }
  if (length(buf)) {
    # The input ends inside an item: checked as a sequence, it says where.
    opts <- a$opts
    opts[1L] <- 1L
    res <- .Call(zucbor_decode, buf, opts, a$max_items, call, a$handlers)
    raise(res[[1L]], base)
  }
  n
}

# cbor_decode_seq()'s arguments, checked, for a stream (mode 3).
zu_seq_args <- function(simplify = c("preserve", "none"),
                        map_keys = c("auto", "map", "string"),
                        tags = c("convert", "keep"),
                        big_integers = c("bigint", "double", "error"),
                        duplicate_keys = FALSE, deterministic = FALSE,
                        max_depth = 256L, max_items = 1e6,
                        tag_handlers = NULL, call = NULL) {
  zu_decode_args(3L, simplify, map_keys, tags, big_integers, duplicate_keys,
                 deterministic, max_depth, 1, max_items, tag_handlers, call)
}

# Reads at most max_size + 1 bytes: one past the limit is enough to know the
# input is too big, and nothing more is ever held (design section 9).
zu_read_bounded <- function(file, max_size, call) {
  zu_arg_limit(max_size, "max_size", 2^53, allow_inf = TRUE, call)
  input <- zu_open_input(file, what = "file", prefix = "zucbor",
                         abort = function(arg, message) zu_invalid_argument(arg, message, call))
  if (input$close) on.exit(close(input$con), add = TRUE)
  chunk <- 65536L
  chunks <- list()
  total <- 0
  repeat {
    want <- if (is.finite(max_size)) min(chunk, max_size + 1 - total) else chunk
    b <- tryCatch(readBin(input$con, "raw", n = want),
                  error = function(e) zu_abort("zucbor_io_error",
                    paste0("could not read input: ", conditionMessage(e)), call = call))
    if (length(b) == 0L) break
    chunks[[length(chunks) + 1L]] <- b
    total <- total + length(b)
    if (total > max_size) zu_raise_fault(zu_size_fault(max_size), call)
  }
  if (length(chunks) == 0L) raw() else unlist(chunks, use.names = FALSE)
}
