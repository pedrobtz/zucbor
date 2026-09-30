# Values R has no native type for (design sections 6 and 7). Users build
# them as well as receive them, so the constructors validate.

#' CBOR values without a native R type
#'
#' Constructors for the four values [cbor_decode()] returns when R has no
#' faithful type of its own. Encoding accepts them too, to write those
#' values back.
#'
#' * `cbor_map()` is a map whose keys are not all non-empty, unique text:
#'   COSE and CWT use small integers as keys, for example. `keys` and
#'   `values` are lists of equal length, in order.
#' * `cbor_tag()` is a tagged item: `tag` is the tag number, `value` its
#'   content.
#' * `cbor_simple()` is a simple value other than `false`, `true`, `null` and
#'   `undefined`: 0 to 19 or 32 to 255.
#' * `cbor_bigint()` is an integer outside what a double holds exactly,
#'   stored as canonical decimal text. It accepts decimal strings, or whole
#'   numbers within 2^53.
#'
#' @param keys,values Lists (or vectors, taken element by element) of equal
#'   length.
#' @param tag A whole number from 0 to 2^53.
#' @param value For `cbor_tag()`, the tagged content; for `cbor_simple()`,
#'   integer simple values.
#' @param x Decimal strings or whole numbers.
#' @return An object of class `cbor_map`, `cbor_tag`, `cbor_simple` or
#'   `cbor_bigint`.
#' @name cbor-values
#' @examples
#' cbor_map(list(1L, 3L), list(-7L, "ES256"))
#' cbor_tag(32, "https://example.com")
#' cbor_simple(16)
#' cbor_bigint("18446744073709551616")
NULL

#' @rdname cbor-values
#' @export
cbor_map <- function(keys = list(), values = list()) {
  call <- sys.call()
  keys <- as.list(keys)
  values <- as.list(values)
  if (length(keys) != length(values)) {
    zu_invalid_argument("values", "`keys` and `values` must have the same length.", call)
  }
  structure(list(keys = unname(keys), values = unname(values)), class = "cbor_map")
}

#' @rdname cbor-values
#' @export
cbor_tag <- function(tag, value) {
  call <- sys.call()
  if (!is.numeric(tag) || length(tag) != 1L || is.na(tag) || tag < 0 ||
      tag != trunc(tag) || tag > 2^53) {
    zu_invalid_argument("tag", "`tag` must be a whole number from 0 to 2^53.", call)
  }
  structure(list(tag = as.numeric(tag), value = value), class = "cbor_tag")
}

#' @rdname cbor-values
#' @export
cbor_simple <- function(value) {
  call <- sys.call()
  ok <- is.numeric(value) && !anyNA(value) && all(value == trunc(value)) &&
    all((value >= 0 & value <= 19) | (value >= 32 & value <= 255))
  if (!ok) {
    zu_invalid_argument("value", paste(
      "`value` must be whole numbers from 0 to 19 or 32 to 255;",
      "20 to 23 are false, true, null and undefined, and 24 to 31 are reserved."), call)
  }
  structure(as.integer(value), class = "cbor_simple")
}

#' @rdname cbor-values
#' @export
cbor_bigint <- function(x) {
  call <- sys.call()
  if (inherits(x, "cbor_bigint")) return(x)
  if (is.numeric(x)) {
    if (!all(is.na(x) | (is.finite(x) & x == trunc(x) & abs(x) <= 2^53))) {
      zu_invalid_argument("x", "numbers must be whole and within 2^53; give larger ones as text.", call)
    }
    x <- ifelse(is.na(x), NA_character_, formatC(x, format = "f", digits = 0, big.mark = ""))
  }
  if (!is.character(x)) {
    zu_invalid_argument("x", "`x` must be decimal strings or whole numbers.", call)
  }
  x <- unname(x)
  ok <- is.na(x) | grepl("^-?(0|[1-9][0-9]*)$", x)
  if (!all(ok)) {
    zu_invalid_argument("x", "`x` must be canonical decimal integers, such as \"-12\".", call)
  }
  x[!is.na(x) & x == "-0"] <- "0"
  structure(x, class = "cbor_bigint")
}

#' @export
format.cbor_bigint <- function(x, ...) format(unclass(x), ...)

#' @export
as.character.cbor_bigint <- function(x, ...) as.vector(unclass(x))

#' @export
as.numeric.cbor_bigint <- function(x, ...) as.numeric(unclass(x))

#' @export
as.double.cbor_bigint <- function(x, ...) as.double(unclass(x))

#' @export
`[.cbor_bigint` <- function(x, i) structure(unclass(x)[i], class = "cbor_bigint")

#' @export
print.cbor_bigint <- function(x, ...) {
  cat("<cbor_bigint[", length(x), "]>\n", sep = "")
  if (length(x)) print(unclass(x), quote = FALSE)
  invisible(x)
}

#' @export
format.cbor_simple <- function(x, ...) paste0("simple(", unclass(x), ")")

#' @export
as.character.cbor_simple <- function(x, ...) format(x)

#' @export
print.cbor_simple <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}

#' @export
format.cbor_tag <- function(x, ...) {
  inner <- if (inherits(x$value, c("cbor_tag", "cbor_map", "cbor_simple"))) format(x$value)[1L]
           else paste(utils::capture.output(utils::str(x$value, give.head = FALSE)), collapse = " ")
  paste0(format(x$tag, scientific = FALSE), "(", trimws(inner), ")")
}

#' @export
as.character.cbor_tag <- function(x, ...) format(x)

#' @export
print.cbor_tag <- function(x, ...) {
  cat("<cbor_tag ", format(x$tag, scientific = FALSE), ">\n", sep = "")
  print(x$value, ...)
  invisible(x)
}

#' @export
length.cbor_map <- function(x) length(unclass(x)$keys)

#' @export
format.cbor_map <- function(x, ...) {
  paste0("<cbor_map: ", length(x), if (length(x) == 1L) " entry>" else " entries>")
}

#' @export
as.character.cbor_map <- function(x, ...) format(x)

#' @export
print.cbor_map <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  m <- unclass(x)
  for (i in seq_along(m$keys)) {
    key <- m$keys[[i]]
    label <- if (is.atomic(key) && length(key) == 1L && !is.raw(key)) format(key)
             else paste(utils::capture.output(utils::str(key, give.head = FALSE)), collapse = " ")
    cat("[[", trimws(label), "]]\n", sep = "")
    print(m$values[[i]], ...)
  }
  invisible(x)
}
