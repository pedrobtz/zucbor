test_that("max_depth counts containers, and a scalar is no level", {
  expect_true(cbor_validate(nested(3), max_depth = 3))
  e <- expect_error(cbor_validate(nested(4), max_depth = 3, error = TRUE),
                    class = "zucbor_depth_limit")
  expect_s3_class(e, "zucbor_limit_error")
  expect_identical(e$limit, "max_depth")
  expect_identical(e$limit_value, 3)
  expect_identical(e$offset, 3)
  expect_true(cbor_validate(hex_raw("00"), max_depth = 1))
})

test_that("a tag is one level of depth", {
  # tag 6 is one TinyCBOR has no rule for, so it may wrap anything.
  expect_true(cbor_validate(nested(3, 0xc6), max_depth = 3))
  expect_error(cbor_validate(nested(4, 0xc6), max_depth = 3, error = TRUE),
               class = "zucbor_depth_limit")
  expect_error(cbor_validate(hex_raw("81 c6 81 00"), max_depth = 2, error = TRUE),
               class = "zucbor_depth_limit")
  expect_true(cbor_validate(hex_raw("81 c6 81 00"), max_depth = 3))
})

test_that("the depth ceiling is exactly what TinyCBOR validates", {
  cap <- zucbor_info()$max_depth_cap
  expect_true(cbor_validate(nested(cap), max_depth = cap))
  expect_true(cbor_validate(nested(cap, 0xc6), max_depth = cap))
  expect_error(cbor_validate(nested(cap + 1L), max_depth = cap, error = TRUE),
               class = "zucbor_depth_limit")
  expect_error(cbor_validate(nested(1), max_depth = cap + 1L),
               class = "zucbor_invalid_argument")
})

test_that("hostile nesting fails at the limit, not on the C stack", {
  expect_error(cbor_validate(nested(1e5), error = TRUE), class = "zucbor_depth_limit")
  expect_error(cbor_validate(nested(1e5, 0xc6), error = TRUE), class = "zucbor_depth_limit")
  expect_error(cbor_validate(c(rep(as.raw(0x9f), 1e5), rep(as.raw(0xff), 1e5)), error = TRUE),
               class = "zucbor_depth_limit")
})

test_that("max_items counts every item, tag and string chunk", {
  x <- hex_raw("83 01 02 03")            # [1, 2, 3]: four items
  expect_true(cbor_validate(x, max_items = 4))
  e <- expect_error(cbor_validate(x, max_items = 3, error = TRUE), class = "zucbor_item_limit")
  expect_identical(e$limit, "max_items")
  expect_true(cbor_validate(hex_raw("c1 00"), max_items = 2))   # tag + content
  expect_false(cbor_validate(hex_raw("c1 00"), max_items = 1))
  chunked <- hex_raw("5f 41 00 41 01 ff")  # string + two chunks
  expect_true(cbor_validate(chunked, max_items = 3))
  expect_false(cbor_validate(chunked, max_items = 2))
})

test_that("max_items refuses a flood of tiny items", {
  flood <- c(as.raw(0x9f), rep(as.raw(0x80), 2e5), as.raw(0xff))
  expect_error(cbor_validate(flood, max_items = 1e5, error = TRUE), class = "zucbor_item_limit")
  expect_true(cbor_validate(flood, max_items = Inf))
})

test_that("max_size is checked before the input is read", {
  x <- hex_raw("83 01 02 03")
  expect_true(cbor_validate(x, max_size = 4))
  e <- expect_error(cbor_validate(x, max_size = 3, error = TRUE), class = "zucbor_size_limit")
  expect_s3_class(e, "zucbor_limit_error")
  expect_identical(e$limit, "max_size")
  expect_identical(e$limit_value, 3)
  expect_true(cbor_validate(x, max_size = Inf))
})

test_that("a length header is never trusted: 2^64 - 1 elements in nine bytes", {
  for (h in c("9b ff ff ff ff ff ff ff ff", "bb ff ff ff ff ff ff ff ff",
              "9a ff ff ff ff", "5b ff ff ff ff ff ff ff ff", "7a ff ff ff ff 00",
              "9b 00 00 00 01 00 00 00 00 00")) {
    expect_error(cbor_validate(hex_raw(h), error = TRUE),
                 class = "zucbor_parse_error", info = h)
  }
})

test_that("limits must be positive whole numbers in range", {
  x <- hex_raw("00")
  bad <- list(0, -1, 0.5, NA, NA_real_, "1", c(1, 2), NULL, TRUE, 2^53 + 2)
  for (v in bad) {
    for (arg in c("max_depth", "max_size", "max_items")) {
      args <- list(x = x)
      args[arg] <- list(v)
      e <- expect_error(do.call(cbor_validate, args), class = "zucbor_invalid_argument",
                        info = paste(arg, deparse(v)))
      expect_identical(e$arg, arg)
    }
  }
  expect_error(cbor_validate(x, max_depth = Inf), class = "zucbor_invalid_argument")
  expect_true(cbor_validate(x, max_size = Inf, max_items = Inf))
  expect_true(cbor_validate(x, max_depth = 1L, max_size = 1, max_items = 1))
})
