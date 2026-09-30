# The condition hierarchy of design section 10. The class is the contract:
# callers branch on it and on the fields below, never on the message.

#' Conditions raised by zucbor
#'
#' Every error zucbor raises carries a condition class, so it can be caught
#' by kind rather than by matching the message, which may change. Every
#' class below inherits from `zucbor_error`.
#'
#' \describe{
#'   \item{`zucbor_invalid_argument`}{An argument was unusable: an input that
#'     is not a raw vector, a flag that is not `TRUE` or `FALSE`, or a limit
#'     that is not a positive whole number within its range.}
#'   \item{`zucbor_parse_error`}{The input is not well-formed CBOR: it ends
#'     early, uses a reserved encoding, has a misplaced "break", or has bytes
#'     after the item.}
#'   \item{`zucbor_invalid_error`}{The input is well-formed but not valid:
#'     a text string that is not UTF-8, or a tag whose content has the wrong
#'     type.}
#'   \item{`zucbor_deterministic_error`}{`deterministic = TRUE` and the input
#'     is not in RFC 8949 core deterministic encoding.}
#'   \item{`zucbor_duplicate_key`}{A map has the same key twice and
#'     `duplicate_keys = FALSE`.}
#'   \item{`zucbor_unrepresentable`}{The input is valid CBOR but holds a
#'     value R cannot: a text string containing U+0000 or longer than an R
#'     string, a tag number beyond 2^53, or an integer beyond 2^53 with
#'     `big_integers = "error"`.}
#'   \item{`zucbor_limit_error`}{A limit was reached. The subclasses
#'     `zucbor_depth_limit`, `zucbor_size_limit` and `zucbor_item_limit` name
#'     which one.}
#' }
#'
#' A condition raised while checking input carries `offset`, the 0-based
#' byte offset of the item at fault, or `NA` when the validator that found
#' the fault reports no position; and `status`, the name of the underlying
#' status, such as `"CborErrorUnexpectedEOF"`. It is there for diagnostics:
#' branch on the class, not on it. A limit error also carries `limit`, the
#' argument's name, such as `"max_depth"`, and `limit_value`. A
#' `zucbor_invalid_argument` condition carries `arg`, the argument at fault.
#'
#' @name zucbor-conditions
#' @examples
#' tryCatch(
#'   cbor_validate(as.raw(c(0x82, 0x01)), error = TRUE),
#'   zucbor_parse_error = function(e) e$offset
#' )
NULL

zu_abort <- function(class, message, ..., call = NULL) {
  stop(structure(
    class = c(class, "zucbor_error", "error", "condition"),
    list(message = message, call = call, ...)
  ))
}

zu_invalid_argument <- function(arg, message, call = NULL) {
  zu_abort("zucbor_invalid_argument", message, arg = arg, call = call)
}

# Status name -> class vector, by the enumerator's name, never by TinyCBOR's
# English. test-conditions.R checks every name C can report is here. Statuses
# that can only come from misuse of TinyCBOR's API, or from code zucbor does
# not compile (the encoder's item counts, CBOR-to-JSON), map to the bare
# zucbor_error: still catchable, never mistaken for a fault in the input.
zu_status_class <- local({
  parse <- "zucbor_parse_error"
  invalid <- "zucbor_invalid_error"
  determ <- "zucbor_deterministic_error"
  dup <- "zucbor_duplicate_key"
  bare <- character()
  list(
    CborErrorGarbageAtEnd = parse,
    CborErrorUnexpectedEOF = parse,
    CborErrorUnexpectedBreak = parse,
    CborErrorUnknownType = parse,
    CborErrorIllegalType = parse,
    CborErrorIllegalNumber = parse,
    CborErrorIllegalSimpleType = parse,
    CborErrorNoMoreStringChunks = parse,
    CborErrorAdvancePastEOF = parse,
    ZU_ERR_ODD_MAP = parse,
    CborErrorInvalidUtf8TextString = invalid,
    CborErrorInappropriateTagForType = invalid,
    CborErrorUnknownSimpleType = invalid,
    CborErrorUnknownTag = invalid,
    CborErrorExcludedType = invalid,
    CborErrorExcludedValue = invalid,
    CborErrorMapKeyNotString = invalid,
    CborErrorOverlongEncoding = determ,
    CborErrorImproperValue = determ,
    CborErrorMapNotSorted = determ,
    CborErrorUnknownLength = determ,
    ZU_ERR_BIGNUM_NOT_PREFERRED = determ,
    CborErrorMapKeysNotUnique = dup,
    CborErrorDuplicateObjectKeys = dup,
    ZU_ERR_DUPLICATE_KEY = dup,
    CborErrorNestingTooDeep = c("zucbor_depth_limit", "zucbor_limit_error"),
    ZU_ERR_DEPTH_LIMIT = c("zucbor_depth_limit", "zucbor_limit_error"),
    ZU_ERR_ITEM_LIMIT = c("zucbor_item_limit", "zucbor_limit_error"),
    ZU_ERR_SIZE_LIMIT = c("zucbor_size_limit", "zucbor_limit_error"),
    CborErrorDataTooLarge = "zucbor_limit_error",
    ZU_ERR_INVALID_DATE = invalid,
    ZU_ERR_KEY_COLLISION = dup,
    ZU_ERR_NUL_IN_TEXT = "zucbor_unrepresentable",
    ZU_ERR_STRING_TOO_LONG = "zucbor_unrepresentable",
    ZU_ERR_BIG_INTEGER = "zucbor_unrepresentable",
    ZU_ERR_TAG_TOO_LARGE = "zucbor_unrepresentable",
    CborUnknownError = bare,
    CborErrorIO = bare,
    CborErrorTooManyItems = bare,
    CborErrorTooFewItems = bare,
    CborErrorUnsupportedType = bare,
    CborErrorUnimplementedValidation = bare,
    CborErrorJsonObjectKeyIsAggregate = bare,
    CborErrorJsonObjectKeyNotString = bare,
    CborErrorJsonNotImplemented = bare,
    CborErrorOutOfMemory = bare,
    CborErrorInternalError = bare
  )
})

zu_fault_message <- function(fault, class) {
  at <- if (is.na(fault$offset)) "" else paste0(" at byte ", format(fault$offset, scientific = FALSE))
  detail <- if (is.na(fault$detail)) "" else paste0(": ", fault$detail)
  switch(class[1L],
    zucbor_parse_error = paste0("CBOR parse error", at, detail),
    zucbor_invalid_error = paste0("invalid CBOR", at, detail),
    zucbor_deterministic_error = paste0("CBOR not in deterministic encoding", at,
                                        if (nzchar(detail)) detail else ": bignum not in preferred form"),
    zucbor_duplicate_key = paste0("duplicate map key", at,
                                  if (identical(fault$status, "ZU_ERR_KEY_COLLISION"))
                                    " once keys are stringified" else ""),
    zucbor_unrepresentable = paste0("CBOR value R cannot hold", at, detail),
    zucbor_depth_limit = paste0("CBOR nested deeper than max_depth = ", fault$limit_value, at),
    zucbor_item_limit = paste0("CBOR has more than max_items = ",
                               format(fault$limit_value, scientific = FALSE), " data items", at),
    zucbor_size_limit = paste0("CBOR input is larger than max_size = ",
                               format(fault$limit_value, scientific = FALSE), " bytes"),
    paste0("CBOR error", at, detail)
  )
}

# Raises the condition for a fault returned by the check phase.
zu_raise_fault <- function(fault, call = NULL) {
  class <- zu_status_class[[fault$status]]
  if (is.null(class)) class <- character()
  zu_abort(class, zu_fault_message(fault, class),
           offset = fault$offset, status = fault$status,
           limit = fault$limit, limit_value = fault$limit_value, call = call)
}
