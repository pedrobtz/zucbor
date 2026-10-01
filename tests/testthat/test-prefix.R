# cbor_decode_prefix(): one item at the start of the input, the rest not
# read (Stage 11, design section 5).

test_that("the item is decoded and consumed counts its bytes", {
  x <- c(cbor_encode(list(a = 1:3)), hex_raw("deadbeef"))
  r <- cbor_decode_prefix(x)
  expect_named(r, c("value", "consumed"))
  expect_identical(r$value, list(a = 1:3))
  expect_identical(r$consumed, length(x) - 4)
  expect_identical(x[-seq_len(r$consumed)], hex_raw("deadbeef"))
})

test_that("an item exactly filling the input is consumed whole", {
  x <- cbor_encode(list("a", 2.5, TRUE))
  expect_identical(cbor_decode_prefix(x), list(value = cbor_decode(x), consumed = as.numeric(length(x))))
})

test_that("trailing valid CBOR is left alone, item by item", {
  x <- cbor_encode_seq(list(1L, "two", list(3L)))
  out <- list()
  while (length(x)) {
    r <- cbor_decode_prefix(x)
    out[[length(out) + 1L]] <- r$value
    x <- x[-seq_len(r$consumed)]
  }
  expect_identical(out, list(1L, "two", I(3L)))
})

test_that("what follows the item is never read, however bad", {
  item <- cbor_encode(1:2)
  rests <- list(
    hex_raw("ff"),                         # a stray break
    hex_raw("1b"),                         # a truncated head
    hex_raw("61ff"),                       # text that is not UTF-8
    nested(5000),                          # deeper than any limit
    hex_raw("9bffffffffffffffff"),         # an absurd length
    as.raw(rep(1, 2000))                   # more items than max_items
  )
  got <- vapply(rests, function(rest) {
    r <- cbor_decode_prefix(c(item, rest), max_depth = 4, max_items = 10, deterministic = TRUE)
    identical(r, list(value = 1:2, consumed = as.numeric(length(item))))
  }, logical(1))
  expect_true(all(got))
})

test_that("the item itself is checked as cbor_decode() checks it", {
  inputs <- list(
    raw(),                                 # no item
    hex_raw("8201"),                       # cut short by the end
    hex_raw("ff00"),                       # a break where an item should be
    c(hex_raw("61ff"), as.raw(0)),         # text that is not UTF-8
    c(nested(10), as.raw(0)),              # too deep
    c(hex_raw("a2616101616101"), as.raw(0)),  # duplicate key
    c(hex_raw("1800"), as.raw(0))          # not deterministic
  )
  got <- fault_class(inputs, function(x) cbor_decode_prefix(x, max_depth = 4, deterministic = TRUE))
  expect_identical(unname(got), c("zucbor_parse_error", "zucbor_parse_error", "zucbor_parse_error",
                                  "zucbor_invalid_error", "zucbor_depth_limit",
                                  "zucbor_duplicate_key", "zucbor_deterministic_error"))
  # max_size is for the input as a whole: all of it is in memory already.
  expect_error(cbor_decode_prefix(c(as.raw(1), raw(100)), max_size = 50), class = "zucbor_size_limit")
})

test_that("every Appendix A example is decoded the same with bytes after it", {
  set.seed(11)
  a <- rfc8949_appendix_a()
  same <- vapply(a$hex, function(h) {
    x <- hex_raw(h)
    want <- cbor_decode(x)
    junk <- as.raw(sample.int(256L, sample.int(8L, 1L), replace = TRUE) - 1L)
    r <- cbor_decode_prefix(c(x, junk))
    identical(r$value, want) && r$consumed == length(x)
  }, logical(1))
  expect_true(all(same), info = paste(a$hex[!same], collapse = " "))
})

test_that("the decoding arguments apply, tag handlers included", {
  x <- c(cbor_encode(cbor_map(list(1L), list(cbor_tag(99, 2L)))), as.raw(0xff))
  r <- cbor_decode_prefix(x, map_keys = "string", tag_handlers = list("99" = function(v) v * 2L))
  expect_identical(r$value, list("1" = 4L))
  expect_error(cbor_decode_prefix(x, simplify = "no"), class = "zucbor_invalid_argument")
  expect_error(cbor_decode_prefix("82"), class = "zucbor_invalid_argument")
})
