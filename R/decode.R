#' Decode CBOR
#'
#' Turns CBOR bytes into ordinary R values. The whole input is checked first
#' -- well-formedness, validity, duplicate keys and the limits, exactly as
#' [cbor_validate()] does -- and nothing is built until that check passes, so
#' a length header cannot make R allocate for data the input does not hold.
#'
#' @section CBOR to R:
#' | CBOR | R |
#' |---|---|
#' | integer | `integer` if it fits, else `double` up to 2^53, else by `big_integers` |
#' | float (half, single, double) | `double`, exactly |
#' | `false` / `true` | `logical` |
#' | `null`, `undefined` | `NULL`, or `NA` inside an atomic vector |
#' | byte string | `raw` |
#' | text string | `character`, UTF-8 |
#' | other simple value | `cbor_simple` |
#' | array | atomic vector when the elements agree, else `list` |
#' | map with non-empty, unique text keys | named `list` |
#' | any other map | `cbor_map` (by `map_keys`) |
#' | tag 0 (date/time text), tag 1 (epoch) | `POSIXct`, UTC |
#' | tag 2, 3 (bignum) | the integer it holds, as for an integer; payloads over 128 bytes stay `cbor_tag` |
#' | tag 100 (days), tag 1004 (full date) | `Date` |
#' | tag 55799 (self-describe) | its content |
#' | any other tag | `cbor_tag` |
#'
#' An array simplifies to an atomic vector only when its elements agree:
#' integers and floats combine to the wider; booleans stay logical, and text
#' stays text; wide integers and integer-valued numbers combine to
#' `cbor_bigint`; `POSIXct` and `Date` stay their class. `null` joins any of
#' them as `NA`. Anything else -- raw vectors, nested arrays and maps, tags,
#' booleans with numbers, a mixture -- is a list. `[]` is `logical(0)`.
#'
#' A one-element array that simplifies is marked with [I()], so that
#' [cbor_encode()] writes it back as an array rather than a single value:
#' decoding and then encoding gives the same bytes for input in
#' deterministic form, apart from the lossy conversions listed in
#' [cbor_encode()].
#'
#' `null` and `undefined` both decode as missing: R has one missing value.
#'
#' @param x A raw vector holding exactly one CBOR data item
#'   (`cbor_decode()`), or an RFC 8742 sequence of zero or more
#'   (`cbor_decode_seq()`).
#' @param simplify `"preserve"` simplifies arrays whose elements agree to
#'   atomic vectors; `"none"` makes every array a list.
#' @param map_keys `"auto"` gives a named list when every key is a non-empty,
#'   unique text string, and a `cbor_map` otherwise. `"map"` always gives a
#'   `cbor_map`. `"string"` always gives a named list, naming each entry by
#'   its text key, or by the key's diagnostic notation when it is not text; it
#'   is lossy, and refuses a map whose keys collide once stringified.
#' @param tags `"convert"` turns the tags in the table into R values and
#'   keeps the rest as `cbor_tag`; `"keep"` makes every tag a `cbor_tag`.
#' @param big_integers What to do with an integer beyond 2^53, which a
#'   double cannot hold exactly: `"bigint"` returns a `cbor_bigint`,
#'   `"double"` the nearest double, and `"error"` refuses the input.
#' @inheritParams cbor_validate
#' @return The decoded value; for `cbor_decode_seq()`, a list with one
#'   element per item.
#' @seealso [cbor_encode()], [cbor_validate()], [cbor_read()], [cbor-values],
#'   [zucbor-conditions].
#' @export
#' @examples
#' cbor_decode(as.raw(c(0x83, 0x01, 0x02, 0x03)))        # [1, 2, 3]
#' cbor_decode(as.raw(c(0xa1, 0x61, 0x61, 0xf5)))        # {"a": true}
#'
#' # A COSE header: integer keys, so a cbor_map.
#' hdr <- cbor_decode(as.raw(c(0xa1, 0x01, 0x26)))       # {1: -7}
#' hdr
#'
#' cbor_decode_seq(as.raw(c(0x01, 0x61, 0x61)))          # 1, then "a"
cbor_decode <- function(x, simplify = c("preserve", "none"),
                        map_keys = c("auto", "map", "string"),
                        tags = c("convert", "keep"),
                        big_integers = c("bigint", "double", "error"),
                        duplicate_keys = FALSE, deterministic = FALSE,
                        max_depth = 256L, max_size = 64 * 1024^2,
                        max_items = 1e6) {
  zu_decode(x, sequence = FALSE, simplify, map_keys, tags, big_integers,
            duplicate_keys, deterministic, max_depth, max_size, max_items,
            call = sys.call())
}

#' @rdname cbor_decode
#' @export
cbor_decode_seq <- function(x, simplify = c("preserve", "none"),
                            map_keys = c("auto", "map", "string"),
                            tags = c("convert", "keep"),
                            big_integers = c("bigint", "double", "error"),
                            duplicate_keys = FALSE, deterministic = FALSE,
                            max_depth = 256L, max_size = 64 * 1024^2,
                            max_items = 1e6) {
  zu_decode(x, sequence = TRUE, simplify, map_keys, tags, big_integers,
            duplicate_keys, deterministic, max_depth, max_size, max_items,
            call = sys.call())
}

zu_decode <- function(x, sequence, simplify, map_keys, tags, big_integers,
                      duplicate_keys, deterministic, max_depth, max_size,
                      max_items, call) {
  zu_arg_raw(x, "x", call)
  simplify <- zu_arg_choice(simplify, "simplify", c("preserve", "none"), call)
  map_keys <- zu_arg_choice(map_keys, "map_keys", c("auto", "map", "string"), call)
  tags <- zu_arg_choice(tags, "tags", c("convert", "keep"), call)
  big_integers <- zu_arg_choice(big_integers, "big_integers",
                                c("bigint", "double", "error"), call)
  zu_arg_flag(duplicate_keys, "duplicate_keys", call)
  zu_arg_flag(deterministic, "deterministic", call)
  zu_arg_limits(max_depth, max_size, max_items, call)
  if (length(x) > max_size) {
    zu_raise_fault(zu_size_fault(max_size), call)
  }
  opts <- c(sequence, deterministic, duplicate_keys, max_depth,
            simplify, map_keys, tags, big_integers) # integer codes
  res <- .Call(zucbor_decode, x, as.integer(opts), as.numeric(max_items), call)
  if (!is.null(res[[1L]])) zu_raise_fault(res[[1L]], call)
  res[[2L]]
}

# The 0-based code of a choice, the way C reads it. The default is the whole
# choice vector, as with match.arg(); anything else must be one of them.
zu_arg_choice <- function(x, arg, choices, call = NULL) {
  if (identical(x, choices)) return(0L)
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% choices) {
    zu_invalid_argument(arg, sprintf("`%s` must be one of %s.", arg,
                                     paste0('"', choices, '"', collapse = ", ")), call)
  }
  match(x, choices) - 1L
}

zu_size_fault <- function(max_size) {
  structure(list(
    status = "ZU_ERR_SIZE_LIMIT", detail = NA_character_, offset = NA_real_,
    limit = "max_size", limit_value = as.numeric(max_size)
  ), class = "zu_fault")
}
