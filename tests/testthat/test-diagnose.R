test_that("diagnostic notation matches RFC 8949 Appendix A", {
  expected <- rfc8949_appendix_a_diagnostic()
  # The two bignum rows: Appendix A's table shows their value, but their
  # diagnostic notation is the tag and its byte string (RFC 8949 section 8).
  expected[["c249010000000000000000"]] <- "2(h'010000000000000000')"
  expected[["c349010000000000000000"]] <- "3(h'010000000000000000')"
  expect_length(expected, 81L)
  for (h in names(expected)) {
    expect_identical(cbor_diagnose(hex_raw(h)), expected[[h]], info = h)
  }
})

test_that("f818 (simple(24)) is refused, as RFC 8949 says it is not well-formed", {
  expect_error(cbor_diagnose(hex_raw("f8 18")), class = "zucbor_parse_error")
})

test_that("numbers print as JavaScript does, with .0 on whole floats", {
  cases <- list(
    "fb 44 b5 2d 02 c7 e1 4a f6" = "1.0e+23",
    "fb 44 15 af 1d 78 b5 8c 40" = "100000000000000000000.0",   # 1e20
    "fb 44 4b 1a e4 d6 e2 ef 50" = "1.0e+21",
    "fb 3e 7a d7 f2 9a bc af 48" = "1.0e-7",
    "fb 3e b0 c6 f7 a0 b5 ed 8d" = "0.000001",
    "fb 40 5e dd 2f 1a 9f be 77" = "123.456",
    "fb c0 5e dd 2f 1a 9f be 77" = "-123.456",
    "f9 3c 00" = "1.0",
    "fa 3f c0 00 00" = "1.5",
    "fb 3f b9 99 99 99 99 99 9a" = "0.1",
    "fb 7f ef ff ff ff ff ff ff" = "1.7976931348623157e+308",
    "fb 00 00 00 00 00 00 00 01" = "5.0e-324",
    "1b ff ff ff ff ff ff ff ff" = "18446744073709551615",
    "3b ff ff ff ff ff ff ff ff" = "-18446744073709551616"
  )
  for (h in names(cases)) expect_identical(cbor_diagnose(hex_raw(h)), cases[[h]], info = h)
})

test_that("every double reads back exactly from its notation", {
  set.seed(8610)
  bits <- matrix(as.raw(sample.int(256, 8 * 20000, replace = TRUE) - 1L), nrow = 8)
  x <- readBin(as.vector(bits), "double", n = 20000, size = 8)
  x <- c(x, 2^-24, 2^-1074, .Machine$double.xmax, .Machine$double.eps, 0.1, 1/3, 1e21, 1e-7)
  ok <- .Call(zucbor:::zucbor_format_roundtrip, x)
  expect_true(all(ok))
})

test_that("text is ASCII, with JSON escapes", {
  expect_identical(cbor_diagnose(cbor_encode("a\"b\\c")), "\"a\\\"b\\\\c\"")
  expect_identical(cbor_diagnose(cbor_encode("\t\n\r\b\f")), "\"\\t\\n\\r\\b\\f\"")
  expect_identical(cbor_diagnose(hex_raw("62 01 7f")), "\"\\u0001\\u007f\"")
  expect_identical(cbor_diagnose(cbor_encode("\u00e9\u6c34\U0001F600")),
                   "\"\\u00e9\\u6c34\\ud83d\\ude00\"")
  # U+0000 is valid CBOR: R cannot hold it as a string, but it prints.
  expect_identical(cbor_diagnose(hex_raw("61 00")), "\"\\u0000\"")
})

test_that("containers, tags, simple values and indefinite lengths", {
  expect_identical(cbor_diagnose(cbor_encode(cbor_map(list(1L, -1L), list(-7L, as.raw(1:2))))),
                   "{1: -7, -1: h'0102'}")
  expect_identical(cbor_diagnose(hex_raw("bf ff")), "{_ }")
  expect_identical(cbor_diagnose(hex_raw("5f ff")), "(_ )")
  expect_identical(cbor_diagnose(hex_raw("c6 c7 f7")), "6(7(undefined))")
  expect_identical(cbor_diagnose(hex_raw("f8 20")), "simple(32)")
  expect_identical(cbor_diagnose(hex_raw("a1 82 01 02 a0")), "{[1, 2]: {}}")
})

test_that("a sequence's items are separated by commas", {
  expect_identical(cbor_diagnose(hex_raw("01 61 61 f6"), sequence = TRUE), "1, \"a\", null")
  expect_identical(cbor_diagnose(raw(), sequence = TRUE), "")
  expect_error(cbor_diagnose(hex_raw("01 02")), class = "zucbor_parse_error")
})

test_that("the check runs first, with its classes and limits", {
  expect_error(cbor_diagnose(hex_raw("82 01")), class = "zucbor_parse_error")
  expect_error(cbor_diagnose(hex_raw("a2 01 00 01 00")), class = "zucbor_duplicate_key")
  expect_error(cbor_diagnose(nested(300)), class = "zucbor_depth_limit")
  expect_error(cbor_diagnose(hex_raw("83 01 02 03"), max_size = 3), class = "zucbor_size_limit")
  expect_identical(cbor_diagnose(hex_raw("a2 01 00 01 00"), duplicate_keys = TRUE), "{1: 0, 1: 0}")
  e <- tryCatch(cbor_diagnose(hex_raw("82 01")), error = identity)
  expect_identical(e$call[[1]], quote(cbor_diagnose))
})

test_that("map_keys = \"string\" names non-text keys by their diagnostic notation", {
  expect_identical(cbor_decode(hex_raw("a1 f9 04 00 01"), map_keys = "string"),
                   list(`0.00006103515625` = 1L))
  expect_identical(cbor_decode(hex_raw("a1 82 01 02 01"), map_keys = "string"), list(`[1, 2]` = 1L))
})
