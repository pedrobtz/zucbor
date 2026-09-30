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
