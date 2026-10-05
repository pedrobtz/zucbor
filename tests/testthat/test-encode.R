test_that("the encoding of a mixed value is byte-identical on every platform", {
  # Generated once from mixed_value() and checked in. A platform, compiler
  # or R version that encodes differently fails here, which is what
  # "deterministic" has to mean (design section 8).
  expected <- paste0(c(
    "ad6362696784c249010000000000000000c3490100000000000000003bffffffffffffff",
    "ff056364617983d903ec6a323032342d30322d3239d903ec6a313937302d30312d3031f6",
    "636c676c83f5f4f6637261775829000102030405060708090a0b0c0d0e0f101112131415",
    "161718191a1b1c1d1e1f20212223242526272863746167d81842810164636f7365a50126",
    "044301020320014101f6617af564696e74738b0017181818ff19010019ffff1a00010000",
    "20373818f664746578748560616169c3bce6b0b4f090859179012c787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878787878787878787878787878787878787878787878787878787878787878787878",
    "787878f6647768656e83c100c1fb41d452d9ec200000f6666e6573746564838282016161",
    "a1616b028101806673696d706c6584e0f3f820f8ff67646f75626c65738e00f98000f93e",
    "00fb3ff199999999999a19ffe019ffe1fb7e37e43c8800759cfa5f8000003bffffffffff",
    "ffffff1b0020000000000002f97e00f97c00f9fc00f669656d7074795f6d6170a0" 
  ), collapse = "")
  expect_identical(paste(format(cbor_encode(mixed_value())), collapse = ""), expected)
})

test_that("scalars encode as design section 7.1 says", {
  expect_cbor(NULL, "f6")
  expect_cbor(NA, "f6")
  expect_cbor(NA_integer_, "f6")
  expect_cbor(NA_real_, "f6")
  expect_cbor(NA_character_, "f6")
  expect_cbor(TRUE, "f5")
  expect_cbor(FALSE, "f4")
  expect_cbor(0L, "00")
  expect_cbor(23L, "17")
  expect_cbor(24L, "18 18")
  expect_cbor(-1L, "20")
  expect_cbor(-25L, "38 18")
  expect_cbor(.Machine$integer.max, "1a 7f ff ff ff")
  expect_cbor(-.Machine$integer.max, "3a 7f ff ff fe")
  expect_cbor("a", "61 61")
  expect_cbor("", "60")
  expect_cbor("ü", "62 c3 bc")
  expect_cbor(as.raw(1:3), "43 01 02 03")
  expect_cbor(raw(), "40")
  expect_cbor(factor("b", levels = c("a", "b")), "61 62")
  expect_cbor(factor(NA), "f6")
})

test_that("whole doubles are integers; everything else is the shortest exact float", {
  expect_cbor(1, "01")
  expect_cbor(-7, "26")
  expect_cbor(1e12, "1b 00 00 00 e8 d4 a5 10 00")
  expect_cbor(2^64 - 2^11, "1b ff ff ff ff ff ff f8 00")   # largest double below 2^64
  expect_cbor(-2^64, "3b ff ff ff ff ff ff ff ff")
  expect_cbor(2^64, "fa 5f 80 00 00")
  expect_cbor(-2^65, "fa e0 00 00 00")
  expect_cbor(neg_zero(), "f9 80 00")
  expect_cbor(0, "00")
  expect_cbor(1.5, "f9 3e 00")
  expect_cbor(65504 + 0.5, "fa 47 7f e0 80")
  expect_cbor(100000 + 0.5, "fa 47 c3 50 40")
  expect_cbor(f64("3ff199999999999a"), "fb 3f f1 99 99 99 99 99 9a")
  expect_cbor(2^-24, "f9 00 01")
  expect_cbor(NaN, "f9 7e 00")
  expect_cbor(Inf, "f9 7c 00")
  expect_cbor(-Inf, "f9 fc 00")
  expect_cbor(f64("7e37e43c8800759c"), "fb 7e 37 e4 3c 88 00 75 9c")
  expect_cbor(f32("7f7fffff"), "fa 7f 7f ff ff")
})

test_that("every half-precision pattern survives decode and encode", {
  expect_identical(.Call(zucbor:::zucbor_half_roundtrip), 0L)
})

test_that("vectors are arrays, length one is a value unless I() or auto_unbox = FALSE", {
  expect_cbor(1:3, "83 01 02 03")
  expect_cbor(integer(), "80")
  expect_cbor(c("a", NA), "82 61 61 f6")
  expect_cbor(I(1), "81 01")
  expect_cbor(1, "81 01", auto_unbox = FALSE)
  expect_cbor(list(a = 1), "a1 61 61 81 01", auto_unbox = FALSE)   # names stay scalar keys
  expect_cbor(matrix(1:4, 2), "84 01 02 03 04")
  expect_cbor(list(1, "a", list()), "83 01 61 61 80")
  expect_cbor(list(), "80")
  expect_cbor(list(as.raw(1), as.raw(2)), "82 41 01 41 02")
})

test_that("named lists and vectors are maps, in deterministic key order", {
  expect_cbor(list(a = 1, b = c(2, 3)), "a2 61 61 01 61 62 82 02 03")
  expect_cbor(list(b = 1, a = 2), "a2 61 61 02 61 62 01")
  expect_cbor(c(b = 1, aa = 2), "a2 61 62 01 62 61 61 02")    # shorter encoding first
  expect_cbor(structure(list(), names = character()), "a0")
  expect_cbor(c(k = 1L), "a1 61 6b 01")
  expect_identical(cbor_encode(list(x = 1, y = 2, z = 3)),
                   cbor_encode(list(z = 3, x = 1, y = 2)))
})

test_that("names must be complete, present and unique", {
  e <- expect_error(cbor_encode(list(a = 1, 2)), class = "zucbor_invalid_argument")
  expect_identical(e$arg, "x")
  expect_error(cbor_encode(stats::setNames(list(1, 2), c("a", NA))), class = "zucbor_invalid_argument")
  expect_error(cbor_encode(c(a = 1, a = 2)), class = "zucbor_duplicate_key")
  expect_error(cbor_encode(list(a = 1, a = 2)), class = "zucbor_duplicate_key")
})

test_that("cbor_map keys are sorted bytewise and compared as encoded", {
  # COSE_Key-like: 1, 3, -1, -2 in bytewise order 01 03 20 21.
  m <- cbor_map(list(-2L, 3L, 1L, -1L), list(0L, -7L, 2L, 1L))
  expect_cbor(m, "a4 01 02 03 26 20 01 21 00")
  # Bytewise, not length-first: 24 (18 18) before -1 (20).
  expect_cbor(cbor_map(list(-1L, 24L), list(0L, 0L)), "a2 18 18 00 20 00")
  expect_cbor(cbor_map(list("a", 1L, as.raw(1)), list(1L, 2L, 3L)), "a3 01 02 41 01 03 61 61 01")
  # 1L and 1 encode identically, so they are the same key.
  expect_error(cbor_encode(cbor_map(list(1L, 1), list(0, 0))), class = "zucbor_duplicate_key")
  expect_cbor(cbor_map(), "a0")
})

test_that("dates, times and wide integers carry their tags", {
  expect_cbor(as.POSIXct(0, origin = "1970-01-01", tz = "UTC"), "c1 00")
  expect_cbor(as.POSIXct(1363896240 + 0.5, origin = "1970-01-01", tz = "UTC"), "c1 fb 41 d4 52 d9 ec 20 00 00")
  expect_cbor(as.POSIXct(-1, origin = "1970-01-01", tz = "UTC"), "c1 20")
  expect_cbor(as.POSIXct(NA), "f6")
  expect_cbor(as.Date("2024-02-29"), "d9 03 ec 6a 32 30 32 34 2d 30 32 2d 32 39")
  expect_cbor(as.Date(NA), "f6")
  expect_cbor(structure(0.75, class = "Date"), "d9 03 ec 6a 31 39 37 30 2d 30 31 2d 30 31")
  expect_cbor(structure(3000000, class = "Date"), "d8 64 1a 00 2d c6 c0")   # year 10183
  expect_cbor(structure(-800000, class = "Date"), "d8 64 3a 00 0c 34 ff")   # year -221
  expect_cbor(structure(1L, class = "Date"), "d9 03 ec 6a 31 39 37 30 2d 30 31 2d 30 32")
  expect_cbor(cbor_bigint("5"), "05")
  expect_cbor(cbor_bigint("-5"), "24")
  expect_cbor(cbor_bigint("18446744073709551615"), "1b ff ff ff ff ff ff ff ff")
  expect_cbor(cbor_bigint("18446744073709551616"), "c2 49 01 00 00 00 00 00 00 00 00")
  expect_cbor(cbor_bigint("-18446744073709551616"), "3b ff ff ff ff ff ff ff ff")
  expect_cbor(cbor_bigint("-18446744073709551617"), "c3 49 01 00 00 00 00 00 00 00 00")
  expect_cbor(cbor_bigint(NA_character_), "f6")
  expect_cbor(cbor_bigint(c("1", "2")), "82 01 02")
  expect_error(cbor_encode(structure("01", class = "cbor_bigint")), class = "zucbor_invalid_argument")
})

test_that("tags and simple values", {
  expect_cbor(cbor_tag(24, as.raw(c(0x81, 0x01))), "d8 18 42 81 01")
  expect_cbor(cbor_tag(55799, list()), "d9 d9 f7 80")
  expect_cbor(cbor_tag(2^53, 1L), "db 00 20 00 00 00 00 00 00 01")
  expect_cbor(cbor_simple(16), "f0")
  expect_cbor(cbor_simple(255), "f8 ff")
  expect_cbor(cbor_simple(c(0, 32)), "82 e0 f8 20")
  expect_error(cbor_encode(structure(20L, class = "cbor_simple")), class = "zucbor_invalid_argument")
  expect_error(cbor_encode(structure(list(tag = -1, value = 1), class = "cbor_tag")),
               class = "zucbor_invalid_argument")
})

test_that("hand-built zucbor objects of the wrong shape are refused", {
  bad <- list(
    structure(list(tag = 1), class = "cbor_tag"),
    structure(list(), class = "cbor_map"),
    structure(1:2, class = "cbor_tag"),
    structure("k", class = "cbor_map"),
    structure(1.5, class = "cbor_simple"),
    structure(TRUE, class = "cbor_simple"),
    structure(5, class = "cbor_bigint")
  )
  got <- fault_class(bad, cbor_encode)
  expect_identical(unname(got), rep("zucbor_invalid_argument", length(bad)))
  frame <- data.frame(a = 1:2)
  frame$a <- structure(c(1.5, 2), class = "cbor_simple")
  expect_error(cbor_encode(frame), class = "zucbor_invalid_argument")
})

test_that("a cbor_tag's content must be what its tag number requires", {
  # design section 8: whatever cbor_encode() writes, cbor_validate() accepts.
  bad <- list(
    cbor_tag(0, 1L), cbor_tag(1, "x"), cbor_tag(2, 1L), cbor_tag(3, "x"),
    cbor_tag(4, 1L), cbor_tag(18, as.raw(1)), cbor_tag(24, 1L), cbor_tag(32, 1L),
    cbor_tag(64, 1L), cbor_tag(100, 1.5), cbor_tag(1004, 1L), cbor_tag(1040, 1L),
    cbor_tag(1, cbor_tag(6, 1L)),
    cbor_tag(0, "not a date"), cbor_tag(1004, "2024x"),
    cbor_tag(65, as.raw(1:3)),                              # 3 bytes of uint16
    cbor_tag(1040, list(c(2L, 2L), 1:3)),                   # 4 cells, 3 elements
    cbor_tag(40, list(integer(), list())),                  # no dimensions
    cbor_tag(40, list(I(-1L), list())),                     # a negative dimension
    cbor_tag(40, list(I(2L), 1:2, 3L)),                     # three parts
    cbor_tag(40, list(I(2L), "ab"))                         # elements not an array
  )
  got <- fault_class(bad, cbor_encode)
  expect_identical(unname(got), rep("zucbor_invalid_argument", length(bad)))
  # The same contents under their tags, of the right kinds, are written.
  expect_cbor(cbor_tag(0, "2013-03-21T20:04:00Z"),
              "c0 74 32 30 31 33 2d 30 33 2d 32 31 54 32 30 3a 30 34 3a 30 30 5a")
  expect_cbor(cbor_tag(1, 1.5), "c1 f9 3e 00")
  expect_cbor(cbor_tag(65, as.raw(1:4)), "d8 41 44 01 02 03 04")
  expect_cbor(cbor_tag(1040, list(c(2L, 1L), 1:2)), "d9 04 10 82 82 02 01 82 01 02")
  expect_cbor(cbor_tag(40, list(I(2L), cbor_tag(64, as.raw(1:2)))), "d8 28 82 81 02 d8 40 42 01 02")
})

test_that("a scalar tag's content is one value even with auto_unbox = FALSE", {
  expect_cbor(cbor_tag(32, "a"), "d8 20 61 61", auto_unbox = FALSE)
  expect_cbor(cbor_tag(1, 0L), "c1 00", auto_unbox = FALSE)
  expect_cbor(cbor_tag(6, 0L), "c6 81 00", auto_unbox = FALSE)    # any content: an array
  expect_error(cbor_encode(cbor_tag(32, I("a"))), class = "zucbor_invalid_argument")
})

test_that("a cbor_tag bignum is written in preferred form", {
  # RFC 8949 section 3.4.3: no leading zeros, and an integer when it fits.
  expect_cbor(cbor_tag(2, raw()), "00")
  expect_cbor(cbor_tag(3, raw()), "20")
  expect_cbor(cbor_tag(2, as.raw(c(0, 0, 1, 0))), "19 01 00")
  expect_cbor(cbor_tag(3, as.raw(rep(0xff, 8))), "3b ff ff ff ff ff ff ff ff")
  expect_cbor(cbor_tag(2, as.raw(c(0, 1, rep(0, 8)))), "c2 49 01 00 00 00 00 00 00 00 00")
  expect_cbor(cbor_tag(3, as.raw(c(1, rep(0, 8)))), "c3 49 01 00 00 00 00 00 00 00 00")
  expect_cbor(list(cbor_tag(2, as.raw(c(0, 5))), 1L), "82 05 01")
  expect_cbor(cbor_map(list(cbor_tag(2, as.raw(c(0, 7)))), list(1L)), "a1 07 01")
  for (x in list(cbor_tag(2, raw()), cbor_tag(2, as.raw(c(0, 1, rep(0, 8)))))) {
    expect_true(cbor_validate(cbor_encode(x), deterministic = TRUE))
  }
})

test_that("values with no CBOR form are refused", {
  matrix_column <- data.frame(a = 1)
  matrix_column$m <- matrix(1:2, 1)
  bad <- list(1i, function() 1, globalenv(), as.POSIXlt("2024-01-01", tz = "UTC"),
              matrix_column, quote(x), list(1, sum))
  for (x in bad) {
    expect_error(cbor_encode(x), class = "zucbor_unsupported_type", info = class(x)[1])
  }
})

test_that("text must be valid UTF-8 and not marked as bytes", {
  latin1 <- iconv("ü", "UTF-8", "latin1")
  expect_cbor(latin1, "62 c3 bc")
  bytes <- "\xff"
  Encoding(bytes) <- "bytes"
  expect_error(cbor_encode(bytes), class = "zucbor_invalid_argument")
  bad <- "\xed\xa0\x80"          # an encoded surrogate
  Encoding(bad) <- "UTF-8"
  expect_error(cbor_encode(bad), class = "zucbor_invalid_argument")
})

test_that("self_describe prefixes tag 55799", {
  expect_cbor(1L, "d9 d9 f7 01", self_describe = TRUE)
  expect_identical(cbor_decode(cbor_encode(list(a = 1L), self_describe = TRUE)), list(a = 1L))
})

test_that("cbor_encode_seq() writes one item per element", {
  expect_identical(cbor_encode_seq(list(1L, "a", NULL)), hex_raw("01 61 61 f6"))
  expect_identical(cbor_encode_seq(list()), raw())
  expect_identical(cbor_decode_seq(cbor_encode_seq(list(1L, "a", 1:3))), list(1L, "a", 1:3))
  expect_identical(cbor_encode_seq(list(1L, 2L), self_describe = TRUE), hex_raw("d9 d9 f7 01 d9 d9 f7 02"))
  expect_error(cbor_encode_seq(1:3), class = "zucbor_invalid_argument")
  expect_error(cbor_encode_seq(data.frame(a = 1)), class = "zucbor_invalid_argument")
})

test_that("the encoder charges depth as the decoder does", {
  nest <- function(d, leaf) { x <- leaf; for (i in seq_len(d)) x <- list(x); x }
  leaves <- list(1L, as.POSIXct(0, origin = "1970-01-01", tz = "UTC"), cbor_tag(6, 1L),
                 c(a = 1L), cbor_map(list(1L), list(2L)), cbor_bigint("18446744073709551616"))
  for (leaf in leaves) {
    for (d in 1:4) {
      x <- nest(d, leaf)
      bytes <- tryCatch(cbor_encode(x, max_depth = 4), zucbor_depth_limit = function(e) NULL)
      decodable <- cbor_validate(cbor_encode(x, max_depth = 20), max_depth = 4)
      # Encodes at max_depth exactly when it decodes at max_depth.
      expect_identical(!is.null(bytes), decodable, info = paste(class(leaf)[1], d))
    }
  }
  e <- expect_error(cbor_encode(nest(300, 1L)), class = "zucbor_depth_limit")
  expect_identical(e$limit, "max_depth")
})

test_that("encode arguments are checked", {
  for (arg in c("auto_unbox", "self_describe")) {
    args <- list(x = 1)
    args[arg] <- list(NA)
    e <- expect_error(do.call(cbor_encode, args), class = "zucbor_invalid_argument")
    expect_identical(e$arg, arg)
  }
  expect_error(cbor_encode(1, max_depth = 0), class = "zucbor_invalid_argument")
  expect_error(cbor_encode(1, max_depth = 1024), class = "zucbor_invalid_argument")
})
