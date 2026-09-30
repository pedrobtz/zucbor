test_that("deterministic input passes", {
  for (h in c("00", "17", "18 18", "39 03 e7", "f9 3c 00", "fb 3f f1 99 99 99 99 99 9a",
              "a2 01 02 03 04", "a2 61 61 01 61 62 82 02 03", "f9 7e 00",
              "c2 49 01 00 00 00 00 00 00 00 00")) {
    expect_true(cbor_validate(hex_raw(h), deterministic = TRUE), info = h)
  }
})

test_that("the round-trip examples of Appendix A are deterministic", {
  a <- rfc8949_appendix_a()
  a <- a[a$roundtrip, ]
  ok <- vapply(a$hex, function(h) cbor_validate(hex_raw(h), deterministic = TRUE), logical(1))
  expect_true(all(ok), info = paste(a$hex[!ok], collapse = " "))
})

test_that("overlong integers, lengths and tags are refused", {
  determ_error("18 01")
  determ_error("19 00 01")
  determ_error("98 01 00")
  determ_error("78 01 61")
  determ_error("d8 01 00")
})

test_that("floats must be the shortest exact width", {
  determ_error("fa 3f 80 00 00")          # 1.0 as single
  determ_error("fb 3f f0 00 00 00 00 00 00")
  determ_error("fb 7f f8 00 00 00 00 00 00")   # NaN as double
  determ_error("f9 7e 01")                # NaN with a payload
})

test_that("indefinite lengths are refused", {
  determ_error("9f ff")
  determ_error("bf ff")
  determ_error("5f ff")
  determ_error("7f ff")
})

test_that("map keys must be in bytewise order", {
  determ_error("a2 03 04 01 02")
  determ_error("a2 61 62 00 61 61 00")
  # Bytewise, not length-first: 24 (18 18) sorts before -1 (20).
  expect_true(cbor_validate(hex_raw("a2 18 18 00 20 00"), deterministic = TRUE))
  determ_error("a2 20 00 18 18 00")
})

test_that("bignums must be in preferred form", {
  determ_error("c2 41 01")                                     # fits an integer
  determ_error("c3 48 ff ff ff ff ff ff ff ff")                # fits: -2^64
  determ_error("c2 4a 00 01 00 00 00 00 00 00 00 00")          # leading zero
  determ_error("c2 40")                                        # empty
  expect_true(cbor_validate(hex_raw("c2 41 01")))             # fine otherwise
})
