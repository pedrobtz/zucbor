# Argument checks shared by every entry point. A limit is a security
# property: one silently replaced by a default, or truncated from a
# fraction, is a limit the caller did not set (design section 11).

zu_arg_raw <- function(x, arg = "x", call = NULL) {
  if (!is.raw(x)) {
    zu_invalid_argument(arg, sprintf(
      "`%s` must be a raw vector, not %s; CBOR is bytes.", arg, zu_describe(x)), call)
  }
  invisible(x)
}

zu_arg_flag <- function(x, arg, call = NULL) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    zu_invalid_argument(arg, sprintf("`%s` must be TRUE or FALSE.", arg), call)
  }
  invisible(x)
}

# A positive whole number no larger than `max`, or Inf where `allow_inf`.
# `max` is the largest finite value C can take exactly.
zu_arg_limit <- function(x, arg, max, allow_inf, call = NULL) {
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 1 &&
    (is.infinite(x) && allow_inf || is.finite(x) && x == trunc(x) && x <= max)
  if (!ok) {
    range <- if (allow_inf) sprintf("a whole number from 1 to %s, or Inf", format(max, scientific = FALSE))
             else sprintf("a whole number from 1 to %s", format(max, scientific = FALSE))
    zu_invalid_argument(arg, sprintf("`%s` must be %s.", arg, range), call)
  }
  invisible(x)
}

zu_arg_limits <- function(max_depth, max_size, max_items, call = NULL) {
  zu_arg_limit(max_depth, "max_depth", zu_max_depth_cap(), allow_inf = FALSE, call)
  zu_arg_limit(max_size, "max_size", 2^53, allow_inf = TRUE, call)
  zu_arg_limit(max_items, "max_items", 2^53, allow_inf = TRUE, call)
}

# TinyCBOR's compile-time ceiling, fetched once: zucbor_build_info() also
# runs a self-test, far too much for every argument check.
zu_cache <- new.env(parent = emptyenv())
zu_max_depth_cap <- function() {
  if (is.null(zu_cache$depth_cap)) zu_cache$depth_cap <- .Call(zucbor_build_info)$max_depth_cap
  zu_cache$depth_cap
}

zu_describe <- function(x) {
  if (is.null(x)) "NULL" else sprintf("a %s vector", typeof(x))
}
