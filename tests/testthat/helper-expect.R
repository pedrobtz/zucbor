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
