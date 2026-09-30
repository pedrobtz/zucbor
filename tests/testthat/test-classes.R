test_that("cbor_map() pairs keys and values", {
  m <- cbor_map(list(1L, "a"), list(TRUE, NULL))
  expect_s3_class(m, "cbor_map")
  expect_length(m, 2L)
  expect_identical(unclass(m)$values, list(TRUE, NULL))
  expect_identical(cbor_map(1:2, c("x", "y")), cbor_map(list(1L, 2L), list("x", "y")))
  expect_length(cbor_map(), 0L)
  expect_error(cbor_map(list(1), list()), class = "zucbor_invalid_argument")
})

test_that("cbor_tag() takes a whole tag number up to 2^53", {
  expect_identical(cbor_tag(32L, "x"), structure(list(tag = 32, value = "x"), class = "cbor_tag"))
  for (bad in list(-1, 1.5, NA, "1", c(1, 2), 2^53 + 2)) {
    expect_error(cbor_tag(bad, 1), class = "zucbor_invalid_argument", info = deparse(bad))
  }
})

test_that("cbor_simple() refuses the reserved and dedicated values", {
  expect_identical(unclass(cbor_simple(c(0, 19, 32, 255))), c(0L, 19L, 32L, 255L))
  for (bad in list(20, 23, 24, 31, 256, -1, 1.5, NA, "16")) {
    expect_error(cbor_simple(bad), class = "zucbor_invalid_argument", info = deparse(bad))
  }
})

test_that("cbor_bigint() holds canonical decimal text", {
  expect_identical(unclass(cbor_bigint(c("0", "-12", "18446744073709551616", NA))),
                   c("0", "-12", "18446744073709551616", NA))
  expect_identical(cbor_bigint(2^53), cbor_bigint("9007199254740992"))
  expect_identical(cbor_bigint(-5), cbor_bigint("-5"))
  expect_identical(cbor_bigint("-0"), cbor_bigint("0"))
  for (bad in list("01", "+1", "1.0", "1e3", " 1", "", 2^53 + 2, 1.5, TRUE)) {
    expect_error(cbor_bigint(bad), class = "zucbor_invalid_argument", info = deparse(bad))
  }
  expect_identical(as.numeric(cbor_bigint("18446744073709551616")), 2^64)
  expect_identical(as.character(cbor_bigint("5")), "5")
  expect_identical(cbor_bigint(c("1", "2"))[2], cbor_bigint("2"))
})

test_that("the classes print", {
  expect_output(print(cbor_bigint("18446744073709551616")), "18446744073709551616")
  expect_output(print(cbor_simple(16)), "simple(16)", fixed = TRUE)
  expect_output(print(cbor_tag(24, as.raw(1))), "cbor_tag 24")
  expect_output(print(cbor_map(list(1L), list("x"))), "cbor_map: 1 entry")
  expect_identical(format(cbor_tag(6, cbor_simple(16))), "6(simple(16))")
})
