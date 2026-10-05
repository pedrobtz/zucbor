test_that("RFC 8949 Appendix A decodes to the values it states", {
  expected <- list(
    "00" = 0L, "01" = 1L, "0a" = 10L, "17" = 23L, "1818" = 24L, "1819" = 25L,
    "1864" = 100L, "1903e8" = 1000L, "1a000f4240" = 1000000L,
    "1b000000e8d4a51000" = 1e12,
    "1bffffffffffffffff" = cbor_bigint("18446744073709551615"),
    "c249010000000000000000" = cbor_bigint("18446744073709551616"),
    "3bffffffffffffffff" = cbor_bigint("-18446744073709551616"),
    "c349010000000000000000" = cbor_bigint("-18446744073709551617"),
    "20" = -1L, "29" = -10L, "3863" = -100L, "3903e7" = -1000L,
    "f90000" = 0, "f93c00" = 1, "fb3ff199999999999a" = f64("3ff199999999999a"),
    "f93e00" = 1.5, "f97bff" = 65504, "fa47c35000" = 1e5, "fa7f7fffff" = f32("7f7fffff"),
    "fb7e37e43c8800759c" = f64("7e37e43c8800759c"), "f90001" = 2^-24,
    "f90400" = 2^-14, "f9c400" = -4, "fbc010666666666666" = f64("c010666666666666"),
    "f97c00" = Inf, "f97e00" = NaN, "f9fc00" = -Inf, "fa7f800000" = Inf,
    "fa7fc00000" = NaN, "faff800000" = -Inf, "fb7ff0000000000000" = Inf,
    "fb7ff8000000000000" = NaN, "fbfff0000000000000" = -Inf,
    "f4" = FALSE, "f5" = TRUE, "f6" = NULL, "f7" = NULL,
    "f0" = cbor_simple(16), "f8ff" = cbor_simple(255),
    "c074323031332d30332d32315432303a30343a30305a" = utc(1363896240),
    "c11a514b67b0" = utc(1363896240), "c1fb41d452d9ec200000" = utc(1363896240 + 0.5),
    "d74401020304" = cbor_tag(23, as.raw(1:4)),
    "d818456449455446" = cbor_tag(24, as.raw(c(0x64, 0x49, 0x45, 0x54, 0x46))),
    "d82076687474703a2f2f7777772e6578616d706c652e636f6d" = cbor_tag(32, "http://www.example.com"),
    "40" = raw(), "4401020304" = as.raw(1:4), "60" = "", "6161" = "a",
    "6449455446" = "IETF", "62225c" = "\"\\", "62c3bc" = "ü",
    "63e6b0b4" = "水", "64f0908591" = "\U00010151",
    "80" = logical(), "83010203" = 1:3, "8301820203820405" = list(1L, 2:3, 4:5),
    "98190102030405060708090a0b0c0d0e0f101112131415161718181819" = 1:25,
    "a0" = structure(list(), names = character()),
    "a201020304" = cbor_map(list(1L, 3L), list(2L, 4L)),
    "a26161016162820203" = list(a = 1L, b = 2:3),
    "826161a161626163" = list("a", list(b = "c")),
    "a56161614161626142616361436164614461656145" = list(a = "A", b = "B", c = "C", d = "D", e = "E"),
    "5f42010243030405ff" = as.raw(1:5), "7f657374726561646d696e67ff" = "streaming",
    "9fff" = logical(), "9f018202039f0405ffff" = list(1L, 2:3, 4:5),
    "9f01820203820405ff" = list(1L, 2:3, 4:5), "83018202039f0405ff" = list(1L, 2:3, 4:5),
    "83019f0203ff820405" = list(1L, 2:3, 4:5),
    "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff" = 1:25,
    "bf61610161629f0203ffff" = list(a = 1L, b = 2:3),
    "826161bf61626163ff" = list("a", list(b = "c")),
    "bf6346756ef563416d7421ff" = list(Fun = TRUE, Amt = -2L)
  )
  a <- rfc8949_appendix_a()
  expect_setequal(names(expected), setdiff(a$hex, "f98000"))
  for (h in names(expected)) {
    expect_identical(cbor_decode(hex_raw(h)), expected[[h]], info = h)
  }
  neg_zero <- cbor_decode(hex_raw("f98000"))
  expect_identical(neg_zero, 0)
  expect_identical(1 / neg_zero, -Inf)
})

test_that("integers take the narrowest exact R type", {
  cases <- list(
    "1a 7f ff ff ff" = 2147483647L,          #  2^31 - 1
    "1a 80 00 00 00" = 2147483648,           #  2^31
    "3a 7f ff ff fe" = -2147483647L,         # -2^31 + 1
    "3a 7f ff ff ff" = -2147483648,          # -2^31: not NA_integer_
    "1b 00 20 00 00 00 00 00 00" = 2^53,
    "3b 00 1f ff ff ff ff ff ff" = -2^53,
    "1b 00 20 00 00 00 00 00 01" = cbor_bigint("9007199254740993"),
    "3b 00 20 00 00 00 00 00 00" = cbor_bigint("-9007199254740993")
  )
  for (h in names(cases)) expect_identical(cbor_decode(hex_raw(h)), cases[[h]], info = h)
})

test_that("big_integers decides beyond 2^53", {
  x <- hex_raw("1b ff ff ff ff ff ff ff ff")
  expect_identical(cbor_decode(x), cbor_bigint("18446744073709551615"))
  expect_identical(cbor_decode(x, big_integers = "double"), 2^64)
  expect_identical(cbor_decode(hex_raw("3b ff ff ff ff ff ff ff ff"), big_integers = "double"), -2^64)
  e <- expect_error(cbor_decode(x, big_integers = "error"), class = "zucbor_unrepresentable")
  expect_identical(e$offset, 0)
  expect_identical(cbor_decode(hex_raw("19 01 00"), big_integers = "error"), 256L)
})

test_that("bignums decode by value", {
  expect_identical(cbor_decode(hex_raw("c2 41 01")), 1L)
  expect_identical(cbor_decode(hex_raw("c3 41 01")), -2L)
  expect_identical(cbor_decode(hex_raw("c2 40")), 0L)
  expect_identical(cbor_decode(hex_raw("c2 43 00 00 05")), 5L)
  expect_identical(cbor_decode(hex_raw("c2 48 01 00 00 00 00 00 00 00")), cbor_bigint("72057594037927936"))
  expect_identical(cbor_decode(hex_raw("c3 49 01 00 00 00 00 00 00 00 00")),
                   cbor_bigint("-18446744073709551617"))
  expect_identical(cbor_decode(hex_raw("c2 49 01 00 00 00 00 00 00 00 00"), big_integers = "double"), 2^64)
  expect_error(cbor_decode(hex_raw("c2 49 01 00 00 00 00 00 00 00 00"), big_integers = "error"),
               class = "zucbor_unrepresentable")
  # 2^1024 - 1 in 128 bytes converts; one byte more stays a tag.
  x128 <- c(hex_raw("c2 58 80"), rep(as.raw(0xff), 128))
  v <- cbor_decode(x128)
  expect_s3_class(v, "cbor_bigint")
  expect_identical(nchar(unclass(v)), 309L)
  expect_identical(substr(unclass(v), 1, 10), "1797693134")
  x129 <- c(hex_raw("c2 58 81"), rep(as.raw(0xff), 129))
  expect_identical(cbor_decode(x129), cbor_tag(2, rep(as.raw(0xff), 129)))
})

test_that("arrays simplify only when their elements agree", {
  cases <- list(
    "82 01 f9 41 00" = c(1, 2.5),
    "82 01 1b ff ff ff ff ff ff ff ff" = cbor_bigint(c("1", "18446744073709551615")),
    "82 1b 00 20 00 00 00 00 00 00 1b ff ff ff ff ff ff ff ff" =
      cbor_bigint(c("9007199254740992", "18446744073709551615")),
    "82 f6 1b ff ff ff ff ff ff ff ff" = cbor_bigint(c(NA, "18446744073709551615")),
    "82 f9 3e 00 1b ff ff ff ff ff ff ff ff" = list(1.5, cbor_bigint("18446744073709551615")),
    "82 f5 1b ff ff ff ff ff ff ff ff" = list(TRUE, cbor_bigint("18446744073709551615")),
    "82 61 61 f6" = c("a", NA),
    "82 f5 01" = list(TRUE, 1L),            # a boolean is not a number
    "82 f5 f9 3e 00" = list(TRUE, 1.5),
    "82 f5 f6" = c(TRUE, NA),
    "82 f5 61 78" = list(TRUE, "x"),
    "82 01 61 61" = list(1L, "a"),
    "82 f6 f6" = c(NA, NA),
    "81 f6" = I(NA),                        # one element: I(), so it re-encodes as [null]
    "82 f6 f7" = c(NA, NA),
    "82 41 01 41 02" = list(as.raw(1), as.raw(2)),
    "82 c1 00 c1 18 3c" = utc(c(0, 60)),
    "82 c1 00 f6" = utc(c(0, NA)),
    "82 d8 64 00 d9 03 ec 6a 31 39 37 30 2d 30 31 2d 30 32" = structure(c(0, 1), class = "Date"),
    "82 c1 00 d8 64 00" = list(utc(0), structure(0, class = "Date")),
    "82 f0 f0" = list(cbor_simple(16), cbor_simple(16)),
    "82 80 80" = list(logical(), logical())
  )
  for (h in names(cases)) expect_identical(cbor_decode(hex_raw(h)), cases[[h]], info = h)
})

test_that("simplify = \"none\" keeps every array a list", {
  expect_identical(cbor_decode(hex_raw("83 01 02 03"), simplify = "none"), list(1L, 2L, 3L))
  expect_identical(cbor_decode(hex_raw("80"), simplify = "none"), list())
  expect_identical(cbor_decode(hex_raw("82 f6 01"), simplify = "none"), list(NULL, 1L))
})

test_that("a map is a named list only when that is faithful", {
  expect_identical(cbor_decode(hex_raw("a2 61 61 01 61 62 02")), list(a = 1L, b = 2L))
  expect_identical(cbor_decode(hex_raw("a1 01 26")), cbor_map(list(1L), list(-7L)))
  expect_identical(cbor_decode(hex_raw("a1 60 01")), cbor_map(list(""), list(1L)))
  expect_identical(cbor_decode(hex_raw("a2 61 61 01 01 02")), cbor_map(list("a", 1L), list(1L, 2L)))
  expect_identical(cbor_decode(hex_raw("a1 41 61 01")), cbor_map(list(charToRaw("a")), list(1L)))
  # A tagged text key is a cbor_tag, so not faithful as a name.
  expect_s3_class(cbor_decode(hex_raw("a1 d8 20 61 61 01")), "cbor_map")
  # Duplicates, when allowed, keep both entries in order.
  expect_identical(cbor_decode(hex_raw("a2 61 61 01 61 61 02"), duplicate_keys = TRUE),
                   cbor_map(list("a", "a"), list(1L, 2L)))
})

test_that("map_keys = \"map\" and \"string\"", {
  expect_identical(cbor_decode(hex_raw("a1 61 61 01"), map_keys = "map"),
                   cbor_map(list("a"), list(1L)))
  expect_identical(cbor_decode(hex_raw("a3 01 61 61 61 62 02 41 01 f5"), map_keys = "string"),
                   list(`1` = "a", b = 2L, `h'01'` = TRUE))
  expect_identical(cbor_decode(hex_raw("a1 f9 3e 00 01"), map_keys = "string"), list(`1.5` = 1L))
  expect_identical(cbor_decode(hex_raw("a1 fb 3f f1 99 99 99 99 99 9a 01"), map_keys = "string"),
                   list(`1.1` = 1L))
  expect_identical(cbor_decode(hex_raw("a3 f9 3c 00 01 f9 7e 00 02 f9 fc 00 03"), map_keys = "string"),
                   list(`1.0` = 1L, `NaN` = 2L, `-Infinity` = 3L))
  e <- expect_error(cbor_decode(hex_raw("a2 01 00 61 31 00"), map_keys = "string"),
                    class = "zucbor_duplicate_key")
  expect_identical(e$status, "ZU_ERR_KEY_COLLISION")
  expect_error(cbor_decode(hex_raw("a2 01 00 61 31 00"), map_keys = "string", duplicate_keys = TRUE),
               class = "zucbor_duplicate_key")
})

test_that("dates and times convert, with offsets applied", {
  t0 <- function(s) c(as.raw(0xc0), text_head(s), charToRaw(s))
  expect_identical(cbor_decode(t0("2013-03-21T20:04:00Z")), utc(1363896240))
  expect_identical(cbor_decode(t0("2013-03-21T21:04:00+01:00")), utc(1363896240))
  expect_identical(cbor_decode(t0("2013-03-21T19:34:00-00:30")), utc(1363896240))
  expect_identical(cbor_decode(t0("2013-03-21t20:04:00.25z")), utc(1363896240 + 0.25))
  expect_identical(cbor_decode(t0("1969-12-31T23:59:59Z")), utc(-1))
  expect_identical(cbor_decode(t0("2016-12-31T23:59:60Z")), utc(1483228800))
  expect_identical(cbor_decode(t0("2000-02-29T00:00:00Z")), utc(951782400))
  for (bad in c("2013-03-21 20:04:00Z", "2013-03-21T20:04:00", "2013-13-21T20:04:00Z",
                "2013-02-29T00:00:00Z", "2013-03-21T24:00:00Z", "2013-03-21T20:04:00.Z",
                "13-03-21T20:04:00Z", "2013-03-21T20:04:00+0100", "2013-03-21T20:04:00Zx")) {
    e <- expect_error(cbor_decode(t0(bad)), class = "zucbor_invalid_error", info = bad)
    expect_identical(e$offset, 0, info = bad)
  }
  expect_identical(cbor_decode(hex_raw("c1 20")), utc(-1))
  expect_identical(cbor_decode(hex_raw("d8 64 19 4e 20")), structure(20000, class = "Date"))
  expect_identical(cbor_decode(hex_raw("d8 64 20")), structure(-1, class = "Date"))
  d <- function(s) c(hex_raw("d9 03 ec"), text_head(s), charToRaw(s))
  expect_identical(cbor_decode(d("2024-02-29")), as.Date("2024-02-29"))
  expect_identical(cbor_decode(d("1970-01-01")), as.Date("1970-01-01"))
  for (bad in c("2023-02-29", "2024-2-29", "2024-02-29T00:00:00Z", "")) {
    expect_error(cbor_decode(d(bad)), class = "zucbor_invalid_error", info = bad)
  }
})

test_that("self-describe is stripped; other tags are kept; tags = \"keep\" keeps all", {
  expect_identical(cbor_decode(hex_raw("d9 d9 f7 83 01 02 03")), 1:3)
  expect_identical(cbor_decode(hex_raw("c6 01")), cbor_tag(6, 1L))
  expect_identical(cbor_decode(hex_raw("c6 c7 01")), cbor_tag(6, cbor_tag(7, 1L)))
  expect_identical(cbor_decode(hex_raw("c1 00"), tags = "keep"), cbor_tag(1, 0L))
  expect_identical(cbor_decode(hex_raw("d9 d9 f7 01"), tags = "keep"), cbor_tag(55799, 1L))
  expect_identical(cbor_decode(hex_raw("c2 41 01"), tags = "keep"), cbor_tag(2, as.raw(1)))
  # Tag 24 is not decoded recursively (design section 6.6).
  expect_identical(cbor_decode(hex_raw("d8 18 42 81 01")), cbor_tag(24, as.raw(c(0x81, 0x01))))
})

test_that("tag numbers beyond 2^53 are unrepresentable", {
  expect_identical(cbor_decode(hex_raw("db 00 20 00 00 00 00 00 00 01")),
                   cbor_tag(2^53, 1L))
  expect_error(cbor_decode(hex_raw("db 00 20 00 00 00 00 00 01 01")),
               class = "zucbor_unrepresentable")
})

test_that("text R cannot hold is unrepresentable; the same text validates", {
  for (h in c("62 61 00", "a1 62 00 61 01", "82 01 7f 61 61 61 00 ff")) {
    e <- expect_error(cbor_decode(hex_raw(h)), class = "zucbor_unrepresentable", info = h)
    expect_identical(e$status, "ZU_ERR_NUL_IN_TEXT")
    expect_true(cbor_validate(hex_raw(h)), info = h)
  }
  # In a tag 0 string it is simply not a date.
  expect_error(cbor_decode(hex_raw("c0 62 31 00")), class = "zucbor_invalid_error")
})

test_that("strings join across chunks", {
  expect_identical(cbor_decode(hex_raw("7f 62 c3 bc 61 61 60 ff")), "üa")
  expect_identical(cbor_decode(hex_raw("5f 40 41 01 42 02 03 ff")), as.raw(1:3))
})

test_that("cbor_decode() wants exactly one item; cbor_decode_seq() any number", {
  expect_error(cbor_decode(raw()), class = "zucbor_parse_error")
  expect_error(cbor_decode(hex_raw("01 02")), class = "zucbor_parse_error")
  expect_identical(cbor_decode_seq(raw()), list())
  expect_identical(cbor_decode_seq(hex_raw("01 61 61 f6 83 01 02 03")), list(1L, "a", NULL, 1:3))
  expect_identical(cbor_decode_seq(hex_raw("f6")), list(NULL))
})

test_that("decoding refuses what validation refuses, with the same class", {
  f <- unlist(rfc8949_not_well_formed(), use.names = FALSE)
  expect_identical(unname(fault_class(lapply(f, hex_raw), cbor_decode)),
                   rep("zucbor_parse_error", length(f)))
  expect_error(cbor_decode(hex_raw("a2 01 00 01 00")), class = "zucbor_duplicate_key")
  expect_error(cbor_decode(hex_raw("61 ff")), class = "zucbor_invalid_error")
  expect_error(cbor_decode(nested(10), max_depth = 5), class = "zucbor_depth_limit")
  expect_error(cbor_decode(hex_raw("83 01 02 03"), max_items = 3), class = "zucbor_item_limit")
  expect_error(cbor_decode(hex_raw("83 01 02 03"), max_size = 3), class = "zucbor_size_limit")
  expect_error(cbor_decode(hex_raw("18 01"), deterministic = TRUE), class = "zucbor_deterministic_error")
  dates <- list(c(hex_raw("c0 6a"), charToRaw("not a date")), c(hex_raw("d9 03 ec 65"), charToRaw("2024x")))
  for (x in dates) {
    v <- expect_error(cbor_validate(x, error = TRUE), class = "zucbor_invalid_error")
    d <- expect_error(cbor_decode(x), class = "zucbor_invalid_error")
    expect_identical(d$status, v$status)
    expect_identical(d$offset, v$offset)
  }
})

test_that("decode arguments are checked", {
  x <- hex_raw("01")
  for (arg in c("simplify", "map_keys", "tags", "big_integers")) {
    for (v in list("nope", NA_character_, c("a", "b"), 1)) {
      args <- list(x = x)
      args[arg] <- list(v)
      e <- expect_error(do.call(cbor_decode, args), class = "zucbor_invalid_argument", info = arg)
      expect_identical(e$arg, arg)
    }
  }
  expect_error(cbor_decode("01"), class = "zucbor_invalid_argument")
  e <- tryCatch(cbor_decode(hex_raw("82 01")), error = identity)
  expect_identical(e$call[[1]], quote(cbor_decode))
})

test_that("the depth limit holds for the build as well as the check", {
  cap <- zucbor_info()$max_depth_cap
  v <- cbor_decode(nested(cap), max_depth = cap)
  for (i in seq_len(cap - 1L)) v <- v[[1]]
  expect_identical(v, I(0L))
})

test_that("a large flat array builds from the checked count", {
  skip_heavy()
  n <- 200000L
  x <- c(hex_raw("9a"), as.raw(c(n %/% 16777216L, (n %/% 65536L) %% 256L, (n %/% 256L) %% 256L, n %% 256L)),
         rep(as.raw(0x01), n))
  expect_identical(cbor_decode(x), rep(1L, n))
  y <- c(hex_raw("9f"), rep(as.raw(0x01), n), hex_raw("ff"))
  expect_identical(cbor_decode(y), rep(1L, n))
})

test_that("a one-element array is marked I(), so it re-encodes as an array", {
  expect_identical(cbor_decode(hex_raw("81 01")), I(1L))
  expect_identical(cbor_decode(hex_raw("81 61 61")), I("a"))
  expect_identical(cbor_decode(hex_raw("81 c1 00")), I(utc(0)))
  expect_identical(cbor_decode(hex_raw("81 81 01")), list(I(1L)))
  expect_identical(cbor_decode(hex_raw("81 01"), simplify = "none"), list(1L))
  # WebAuthn's x5c is often an array of one certificate.
  x <- hex_raw("a1 63 78 35 63 81 43 01 02 03")
  v <- cbor_decode(x)
  expect_identical(v, list(x5c = list(as.raw(1:3))))
  expect_identical(cbor_encode(v), x)
  y <- hex_raw("a1 61 6b 81 01")
  expect_identical(cbor_encode(cbor_decode(y)), y)
})
