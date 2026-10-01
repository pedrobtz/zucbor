# Helpers shared by the test files. They live here, not at the top of a
# test file, because devtools::test(shuffle = TRUE) reorders a file's
# top-level expressions, definitions included.

nested <- function(n, byte = 0x81) c(rep(as.raw(byte), n), as.raw(0x00))

dup_error <- function(hex, ...) {
  expect_error(cbor_validate(hex_raw(hex), error = TRUE, ...), class = "zucbor_duplicate_key")
}

determ_error <- function(hex) {
  expect_error(cbor_validate(hex_raw(hex), deterministic = TRUE, error = TRUE),
               class = "zucbor_deterministic_error", info = hex)
}

# The head of a text string of s's UTF-8 length.
text_head <- function(s) {
  n <- length(charToRaw(s))
  if (n < 24) as.raw(0x60 + n) else if (n < 256) as.raw(c(0x78, n)) else stop("too long")
}

utc <- function(secs) structure(secs, class = c("POSIXct", "POSIXt"), tzone = "UTC")

# A double from its IEEE 754 bits, big-endian hex. R's parser does not round
# every decimal literal correctly where long double is only a double (macOS
# arm64 at Stage 3: 5.960464477539063e-08 was one ulp off), so any float a
# test compares exactly is built from its bits, or from arithmetic that is
# exact.
f64 <- function(hex) readBin(hex_raw(hex), "double", size = 8L, endian = "big")
f32 <- function(hex) readBin(hex_raw(hex), "double", size = 4L, endian = "big")

# Skips a test that allocates millions of R objects. It checks a limit or a
# code path, not memory safety, and under gctorture it would take hours;
# native-checks.yaml sets ZUCBOR_SKIP_HEAVY for the gctorture job.
skip_heavy <- function() {
  skip_if(nzchar(Sys.getenv("ZUCBOR_SKIP_HEAVY")), "ZUCBOR_SKIP_HEAVY is set")
}

# cbor_encode(x) is exactly these bytes.
expect_cbor <- function(x, hex, ...) {
  expect_identical(cbor_encode(x, ...), hex_raw(hex), info = hex)
}

# A value exercising every encoder path, for the cross-platform fixture.
# R's byte-code compiler folds the literal -0 to +0 (R 4.5.2), so a test
# that needs negative zero makes it at run time.
neg_zero <- function() {
  z <- 0
  -z
}

mixed_value <- function() {
  list(
    ints = c(0L, 23L, 24L, 255L, 256L, 65535L, 65536L, -1L, -24L, -25L, NA),
    doubles = c(0, neg_zero(), 1.5, f64("3ff199999999999a"), 65504, 65505, f64("7e37e43c8800759c"), 2^64, -2^64, 2^53 + 2, NaN, Inf, -Inf, NA),
    text = c("", "a", "\u00fc\u6c34\U00010151", strrep("x", 300), NA),
    raw = as.raw(0:40),
    lgl = c(TRUE, FALSE, NA),
    when = as.POSIXct(c(0, 1363896240 + 0.5, NA), origin = "1970-01-01", tz = "UTC"),
    day = as.Date(c("2024-02-29", "1970-01-01", NA)),
    big = cbor_bigint(c("18446744073709551616", "-18446744073709551617", "-18446744073709551616", "5")),
    cose = cbor_map(list(1L, 4L, -1L, "z", as.raw(1)), list(-7, as.raw(1:3), 1L, TRUE, NULL)),
    tag = cbor_tag(24, as.raw(c(0x81, 0x01))),
    simple = cbor_simple(c(0, 19, 32, 255)),
    nested = list(list(list(1, "a"), c(k = 2)), I(1), list()),
    empty_map = structure(list(), names = character())
  )
}

# The condition class each input raises, or "ok": for checking hundreds of
# inputs with one expectation, since testthat's per-expectation overhead
# dominates the suite's run time otherwise.
fault_class <- function(inputs, f = function(x) cbor_validate(x, error = TRUE)) {
  vapply(inputs, function(x) tryCatch({f(x); "ok"}, error = function(e) class(e)[1]), "")
}

# Registers an as_cbor() method for the calling test only. A method defined
# inside test_that() is invisible to S3 dispatch, which looks in the
# namespace's registry and the global environment, not the test's frame.
local_as_cbor <- function(class, method, env = parent.frame()) {
  table <- get(".__S3MethodsTable__.", envir = asNamespace("zucbor"))
  name <- paste0("as_cbor.", class)
  assign(name, method, envir = table)
  withr::defer(rm(list = name, envir = table), envir = env)
}

# The typed array tag `tag` (RFC 8746) around the bytes `b`.
typed_item <- function(tag, b) {
  head <- cbor_encode(cbor_tag(tag, raw()))          # the tag, then 0x40
  c(head[-length(head)], cbor_encode(b))
}
