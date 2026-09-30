test_that("the pinned TinyCBOR is the one linked", {
  # A literal, because tools/ is not installed: bumping TinyCBOR means
  # changing tools/update-tinycbor's input and this line together.
  expect_identical(zucbor_info()$tinycbor_version, "7.0.0")
})

test_that("the bundled validator accepts a known-good item", {
  expect_true(zucbor_info()$smoke_ok)
})

test_that("the depth ceiling is the deepest item TinyCBOR validates", {
  # CBOR_PARSER_MAX_RECURSIONS is 1024, but the validator charges a level
  # before testing it, so 1023 levels pass and 1024 fail.
  expect_identical(zucbor_info()$max_depth_cap, 1023L)
})

test_that("default limits are the design's", {
  lim <- zucbor_info()$limits
  expect_identical(lim$max_depth, 256L)
  expect_identical(lim$max_size, 64 * 1024^2)
  expect_identical(lim$max_items, 1e6)
  expect_lte(lim$max_depth, zucbor_info()$max_depth_cap)
})

test_that("zucbor_info() prints without error", {
  expect_output(print(zucbor_info()), "TinyCBOR:  7.0.0", fixed = TRUE)
})
