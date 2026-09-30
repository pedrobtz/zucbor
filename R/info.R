# Default decoding limits, design section 11. Every decode entry point takes
# its defaults from here, so zucbor_info() reports what the decoder enforces.
zu_default_limits <- function() {
  list(max_depth = 256L, max_size = 64 * 1024^2, max_items = 1e6)
}

#' Build information
#'
#' Reports the bundled TinyCBOR version, the compile-time ceiling on nesting
#' depth, and the default decoding limits.
#'
#' @return A list of class `zucbor_info` with elements:
#'   * `tinycbor_version`: version of the bundled TinyCBOR, e.g. `"7.0.0"`.
#'   * `max_depth_cap`: the largest `max_depth` any decoder accepts, set by
#'     TinyCBOR's compile-time recursion limit.
#'   * `limits`: the default `max_depth`, `max_size` (bytes) and `max_items`.
#'   * `smoke_ok`: `TRUE` if the bundled validator accepts a known-good item.
#' @export
#' @examples
#' zucbor_info()
zucbor_info <- function() {
  info <- .Call(zucbor_build_info)
  structure(
    list(
      tinycbor_version = info$tinycbor_version,
      max_depth_cap = info$max_depth_cap,
      limits = zu_default_limits(),
      smoke_ok = info$smoke_ok
    ),
    class = "zucbor_info"
  )
}

#' @export
format.zucbor_info <- function(x, ...) {
  lim <- x$limits
  c(
    "<zucbor_info>",
    paste0("TinyCBOR:  ", x$tinycbor_version),
    paste0("max_depth: ", lim$max_depth, " (at most ", x$max_depth_cap, ")"),
    paste0("max_size:  ", format(lim$max_size, scientific = FALSE), " bytes"),
    paste0("max_items: ", format(lim$max_items, scientific = FALSE)),
    paste0("self-test: ", if (isTRUE(x$smoke_ok)) "ok" else "FAILED")
  )
}

#' @export
print.zucbor_info <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
