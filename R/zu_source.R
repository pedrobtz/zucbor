# zu_source.R -- turning what a user passes into a readable connection.
#
# Origin: zuxml 0.1.0, R/zu_source.R. This file is meant to be copied
# verbatim into sibling packages (zuhtml, zujson, zuyaml), together with
# src/zu_source.h; keep this line current so drift between copies is
# visible. It knows nothing about the format being read.

# The kinds of input a reader accepts, resolved to a connection:
#
# - a connection is used as is;
# - a string with an http, https, ftp, ftps or file scheme is a url();
# - any other string is a path, checked here so the errors name the problem
#   rather than surfacing as a base R message about a non-regular file.
#
# Follows readBin()'s convention: an unopened connection is opened in "rb"
# and must be closed by the caller once done (the `close` flag says so);
# an open one must already be binary, is read from its current position,
# and is left open. The caller registers close() with on.exit() itself so
# the connection lives exactly as long as the caller's frame.
#
# `what` names the argument in error messages. `abort(arg, message)` raises
# the package's own classed invalid-argument condition, and `fail(message)`
# its I/O condition, for a URL or file that cannot be opened; the defaults
# are plain errors with `prefix`, for a package that has none.
zu_open_input <- function(x, what = "path", prefix = "zuxml",
                          abort = function(arg, message)
                            stop(paste0(prefix, ": ", message), call. = FALSE),
                          fail = function(message)
                            stop(paste0(prefix, ": ", message), call. = FALSE)) {
  if (!inherits(x, "connection")) {
    if (!is.character(x) || length(x) != 1L || is.na(x))
      abort(what, sprintf("`%s` must be a single file path, URL or connection",
                          what))
    if (grepl("^(https?|ftps?|file)://", x, ignore.case = TRUE)) {
      # A scheme is case-insensitive by RFC 3986, but url() rejects "HTTP://".
      x <- url(sub("^([A-Za-z]+)://", "\\L\\1://", x, perl = TRUE))
    } else {
      # file.exists() is TRUE for a directory.
      if (dir.exists(x)) abort(what, sprintf("not a file: %s", x))
      if (!file.exists(x)) abort(what, sprintf("no such file: %s", x))
      x <- file(x)
    }
  }
  if (!isOpen(x)) {
    zu_open_rb(x, fail)
    return(list(con = x, close = TRUE))
  }
  if (!identical(summary(x)$text, "binary"))
    abort(what, "an open connection must be in binary mode (\"rb\")")
  list(con = x, close = FALSE)
}

# open(x, "rb"), with a failure raised through `fail`. R reports a failed
# open as a warning that names the cause ("HTTP status was '404 Not
# Found'", "Permission denied") followed by an error that does not, so the
# warning becomes the message. The connection that could not be opened is
# destroyed, rather than left for the garbage collector to warn about.
zu_open_rb <- function(x, fail) {
  why <- character()
  ok <- tryCatch(
    withCallingHandlers(
      {
        open(x, "rb")
        TRUE
      },
      warning = function(w) {
        why <<- c(why, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      why <<- c(why, conditionMessage(e))
      FALSE
    }
  )
  if (!ok) {
    try(close(x), silent = TRUE)
    fail(why[[1L]])
  }
  # An open that succeeded keeps its warnings.
  for (w in why) warning(w, call. = FALSE)
  invisible(x)
}

# The rest of a connection as one raw vector, for the cases that cannot be
# streamed -- an encoding that must be transcoded whole, for instance.
zu_read_all <- function(con, chunk = 65536L) {
  chunks <- list()
  repeat {
    b <- readBin(con, "raw", n = chunk)
    if (length(b) == 0L) break
    chunks[[length(chunks) + 1L]] <- b
  }
  if (length(chunks) == 0L) raw() else unlist(chunks, use.names = FALSE)
}
