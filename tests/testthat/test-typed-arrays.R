# RFC 8746 typed and multi-dimensional arrays: Stage 12, design section 6.9.

test_that("every integer typed array decodes, in either byte order", {
  le <- function(v, size) unlist(lapply(v, function(x) as.raw((x %/% 256^(0:(size - 1))) %% 256)))
  be <- function(v, size) unlist(lapply(v, function(x) rev(as.raw((x %/% 256^(0:(size - 1))) %% 256))))
  u8 <- c(0, 1, 255)
  expect_identical(cbor_decode(typed_item(64, le(u8, 1))), c(0L, 1L, 255L))
  expect_identical(cbor_decode(typed_item(68, le(u8, 1))), c(0L, 1L, 255L))      # clamped
  expect_identical(cbor_decode(typed_item(72, le(c(0, 127, 128, 255), 1))), c(0L, 127L, -128L, -1L))
  u16 <- c(0, 258, 65535)
  for (tag in c(65, 69)) {
    b <- if (tag == 65) be(u16, 2) else le(u16, 2)
    expect_identical(cbor_decode(typed_item(tag, b)), c(0L, 258L, 65535L))
  }
  s16 <- c(1, 32768, 65535)                 # 1, -32768, -1 as two's complement
  expect_identical(cbor_decode(typed_item(73, be(s16, 2))), c(1L, -32768L, -1L))
  expect_identical(cbor_decode(typed_item(77, le(s16, 2))), c(1L, -32768L, -1L))
  u32 <- c(0, 2^31, 2^32 - 1)
  expect_identical(cbor_decode(typed_item(66, be(u32, 4))), u32)                 # unsigned 32: double
  expect_identical(cbor_decode(typed_item(70, le(u32, 4))), u32)
  s32 <- c(5, 2^32 - 5, 2^31)               # 5, -5, INT_MIN (R's NA)
  expect_identical(cbor_decode(typed_item(74, be(s32, 4))), c(5L, -5L, NA))
  expect_identical(cbor_decode(typed_item(78, le(s32, 4))), c(5L, -5L, NA))
  u64 <- c(0, 2^53)
  expect_identical(cbor_decode(typed_item(67, be(u64, 8))), u64)
  expect_identical(cbor_decode(typed_item(71, le(u64, 8))), u64)
  # -1 and -2^53 as sint64.
  s64 <- c(hex_raw("ffffffffffffffff"), hex_raw("ffe0000000000000"))
  expect_identical(cbor_decode(typed_item(75, s64)), c(-1, -2^53))
  expect_identical(cbor_decode(typed_item(79, c(rev(s64[1:8]), rev(s64[9:16])))), c(-1, -2^53))
})

test_that("64-bit elements beyond 2^53 follow big_integers", {
  x <- typed_item(71, c(as.raw(c(1, 0, 0, 0, 0, 0, 0, 0)), as.raw(rep(0xff, 8))))   # 1, 2^64 - 1
  v <- cbor_decode(x)
  expect_s3_class(v, "cbor_bigint")
  expect_identical(as.character(v), c("1", "18446744073709551615"))
  expect_identical(cbor_decode(x, big_integers = "double"), c(1, 2^64))
  expect_error(cbor_decode(x, big_integers = "error"), class = "zucbor_unrepresentable")
  m <- cbor_decode(typed_item(75, hex_raw("8000000000000000")))                     # INT64_MIN
  expect_identical(as.character(m), "-9223372036854775808")
})

test_that("float typed arrays decode exactly, every bit kept", {
  half <- hex_raw("3c00 7bff 8000 7c00 7e00")        # 1, 65504, -0, Inf, NaN
  v <- cbor_decode(typed_item(80, half))
  expect_identical(v[1:4], c(1, 65504, neg_zero(), Inf))
  expect_identical(1 / v[3], -Inf)
  expect_true(is.nan(v[5]))
  swap2 <- function(b) as.vector(matrix(b, 2)[2:1, ])
  expect_identical(cbor_decode(typed_item(84, swap2(half))), v)
  f32 <- hex_raw("3fc00000 7f7fffff")
  expect_identical(cbor_decode(typed_item(81, f32)), c(1.5, f32("7f7fffff")))
  expect_identical(cbor_decode(typed_item(85, c(rev(f32[1:4]), rev(f32[5:8])))), c(1.5, f32("7f7fffff")))
  na <- writeBin(NA_real_, raw(), endian = "little")
  v <- cbor_decode(typed_item(86, c(writeBin(c(0.1, -0), raw(), endian = "little"), na)))
  expect_identical(v, c(0.1, neg_zero(), NA_real_))
  expect_true(is.na(v[3]) && !is.nan(v[3]))
  expect_identical(cbor_decode(typed_item(82, writeBin(c(0.1, 2), raw(), endian = "big"))), c(0.1, 2))
})

test_that("binary128 and a typed array's wrong length", {
  expect_s3_class(cbor_decode(typed_item(87, raw(16))), "cbor_tag")
  expect_s3_class(cbor_decode(typed_item(83, raw(32))), "cbor_tag")
  bad <- list(typed_item(86, raw(7)), typed_item(87, raw(8)), typed_item(77, raw(3)), typed_item(70, raw(6)),
              c(hex_raw("d856"), cbor_encode(1:2)), typed_item(78, raw(5)))
  got <- fault_class(bad)
  expect_identical(unname(got), rep("zucbor_invalid_error", length(bad)))
  e <- tryCatch(cbor_decode(c(hex_raw("82 01"), typed_item(86, raw(7)))), error = identity)
  expect_identical(e$offset, 2)
  expect_identical(e$status, "ZU_ERR_TYPED_ARRAY")
  # Tag 76 is reserved, so it is any other tag.
  expect_s3_class(cbor_decode(typed_item(76, raw(3))), "cbor_tag")
})

test_that("a typed array is one element of its parent, and one element is I()", {
  x <- cbor_encode(list(1L, cbor_tag(86, writeBin(c(1, 2), raw(), endian = "little"))))
  expect_identical(cbor_decode(x), list(1L, c(1, 2)))
  one <- cbor_decode(typed_item(86, writeBin(2.5, raw(), endian = "little")))
  expect_identical(one, I(2.5))
  expect_identical(cbor_decode(typed_item(86, raw())), numeric(0))
})

test_that("tags 1040 and 40 decode to matrices and arrays in R's order", {
  m <- cbor_decode(hex_raw("d90410 82 82 02 03 86 01 02 03 04 05 06"))
  expect_identical(m, matrix(1:6, 2))
  r <- cbor_decode(hex_raw("d828 82 82 02 03 86 01 02 03 04 05 06"))   # row-major
  expect_identical(r, matrix(1:6, 2, byrow = TRUE))
  # Three dimensions, row-major: element [i, j, k] is at ((i * 3) + j) * 4 + k.
  a <- cbor_decode(cbor_encode(cbor_tag(40, list(c(2L, 3L, 4L), 0:23))))
  want <- array(0L, c(2, 3, 4))
  for (i in 0:1) for (j in 0:2) for (k in 0:3) want[i + 1, j + 1, k + 1] <- ((i * 3L) + j) * 4L + k
  expect_identical(a, want)
  # A typed array as the elements; one dimension; no elements.
  t <- cbor_decode(c(hex_raw("d90410 82 82 02 02"), typed_item(86, writeBin(c(1, 2, 3, 4), raw(), endian = "little"))))
  expect_identical(t, matrix(c(1, 2, 3, 4), 2))
  expect_identical(cbor_decode(hex_raw("d90410 82 81 03 83 61 61 61 62 61 63")), array(c("a", "b", "c"), 3))
  expect_identical(cbor_decode(hex_raw("d90410 82 82 00 03 80")), matrix(logical(0), 0, 3))
  # One element: a 1 x 1 matrix, without I().
  expect_identical(cbor_decode(hex_raw("d90410 82 82 01 01 81 07")), matrix(7L, 1, 1))
  # Elements that do not simplify make a list matrix.
  expect_identical(cbor_decode(hex_raw("d90410 82 82 01 02 82 01 61 61")), matrix(list(1L, "a"), 1, 2))
})

test_that("a multi-dimensional array's shape is checked before anything is built", {
  bad <- c(
    "d90410 82 82 01 02 83 01 02 03",          # 2 dimensions' product is 2, 3 elements
    "d90410 82 80 80",                          # no dimensions
    "d90410 82 81 20 81 01",                    # a negative dimension
    "d90410 82 81 c1 01 81 01",                 # a tagged dimension
    "d90410 83 81 01 81 01 81 01",              # three parts
    "d90410 81 81 00",                          # one part
    "d90410 82 a0 81 01",                       # dimensions not an array
    "d90410 82 81 01 a1 01 01",                 # elements a map
    "d90410 82 81 01 d863 81 01",               # elements under another tag
    "d90410 82 81 02 d84e 44 01000000",         # a typed array of 1 for 2
    "d90410 82 82 1b ffffffffffffffff 1b ffffffffffffffff 80",  # a product past 2^64
    "d90410 a0",                                # content not an array
    "d828 82 81 02 81 01"
  )
  got <- fault_class(lapply(bad, hex_raw))
  expect_identical(unname(got), rep("zucbor_invalid_error", length(bad)))
  # A dimension R cannot hold, with no elements: valid CBOR, refused in R.
  expect_error(cbor_decode(hex_raw("d90410 82 82 1a 80000000 00 80")), class = "zucbor_unrepresentable")
})

test_that("tags = \"keep\" and tag handlers apply to typed arrays", {
  x <- typed_item(86, writeBin(c(1, 2), raw(), endian = "little"))
  expect_s3_class(cbor_decode(x, tags = "keep"), "cbor_tag")
  expect_identical(cbor_decode(x, tag_handlers = list("86" = length)), 16L)
  m <- c(hex_raw("d90410 82 82 01 02"), x)
  expect_identical(cbor_decode(m, tag_handlers = list("1040" = function(v) v[[1]])), c(1L, 2L))
  # A handler for the elements: its result is used if it is a vector of the
  # right length, and kept in a cbor_tag otherwise.
  expect_identical(cbor_decode(m, tag_handlers = list("86" = function(b) c(5L, 6L))), matrix(5:6, 1))
  shared <- c(5L, 6L)
  v <- cbor_decode(m, tag_handlers = list("86" = function(b) shared))
  expect_identical(shared, c(5L, 6L))                 # not modified in place
  kept <- cbor_decode(m, tag_handlers = list("86" = function(b) "no"))
  expect_s3_class(kept, "cbor_tag")
  expect_identical(kept$value[[2]], "no")
})

test_that("typed_arrays = TRUE writes numeric vectors as tags 86 and 78", {
  expect_cbor(c(1.5, -2), "d856 50 000000000000f83f 00000000000000c0" |> gsub(pattern = " ", replacement = ""),
              typed_arrays = TRUE)
  expect_cbor(c(1L, NA, -1L), "d84e4c01000000 00000080 ffffffff" |> gsub(pattern = " ", replacement = ""),
              typed_arrays = TRUE)
  # A whole double stays a float; a single value is still a single value.
  expect_cbor(c(1, 2), "d856 50 000000000000f03f 0000000000000040" |> gsub(pattern = " ", replacement = ""),
              typed_arrays = TRUE)
  expect_cbor(2.5, "f94100", typed_arrays = TRUE)
  expect_cbor(I(2.5), "d856 48 0000000000000440" |> gsub(pattern = " ", replacement = ""), typed_arrays = TRUE)
  expect_cbor(1L, "d84e 44 01000000" |> gsub(pattern = " ", replacement = ""), typed_arrays = TRUE, auto_unbox = FALSE)
  expect_cbor(integer(0), "d84e40", typed_arrays = TRUE)
  # Classes keep their own form; names make a map; logical and text are not typed.
  expect_cbor(factor(c("a", "b")), "826161 6162" |> gsub(pattern = " ", replacement = ""), typed_arrays = TRUE)
  expect_cbor(as.Date(c(0, 1)), cbor_encode(as.Date(c(0, 1))) |> paste(collapse = ""), typed_arrays = TRUE)
  expect_cbor(c(a = 1, b = 2), "a2616101616202", typed_arrays = TRUE)
  expect_cbor(c(TRUE, FALSE), "82f5f4", typed_arrays = TRUE)
  # Off by default: 0.1.0's bytes.
  expect_cbor(c(1.5, -2), "82f93e00 21" |> gsub(pattern = " ", replacement = ""))
  expect_error(cbor_encode(1, typed_arrays = NA), class = "zucbor_invalid_argument")
})

test_that("typed_arrays = TRUE writes matrices and arrays as tag 1040", {
  expect_cbor(matrix(1:4, 2), "d90410 82 82 02 02 d84e 50 01000000 02000000 03000000 04000000" |>
                gsub(pattern = " ", replacement = ""), typed_arrays = TRUE)
  expect_cbor(matrix(c("a", "b"), 1), "d90410 82 82 01 02 82 6161 6162" |> gsub(pattern = " ", replacement = ""),
              typed_arrays = TRUE)
  expect_cbor(matrix(list(1L, "a"), 1), "d90410 82 82 01 02 82 01 6161" |> gsub(pattern = " ", replacement = ""),
              typed_arrays = TRUE)
  # Without the option a matrix is a flat array, as in 0.1.0.
  expect_cbor(matrix(1:4, 2), "8401020304")
})

test_that("R to CBOR to R is identical for numeric vectors, matrices and arrays", {
  values <- list(
    c(1.5, NA, NaN, neg_zero(), Inf, -Inf, f64("7fefffffffffffff"), 5e-324),
    c(1L, NA, .Machine$integer.max, -.Machine$integer.max),
    I(0.1), I(7L), numeric(0), integer(0),
    matrix(c(0.5, NA, 3, 4, NaN, -Inf), 2), matrix(1:6, 3),
    array(seq(0.25, 6, by = 0.25), c(2, 3, 4)), array(1:5, 5),
    matrix(c("x", NA, "z", "w"), 2), matrix(c(TRUE, NA), 1),
    list(a = c(1, 2), b = list(matrix(1:4, 2), 3:5))
  )
  for (v in values) {
    back <- cbor_decode(cbor_encode(v, typed_arrays = TRUE))
    expect_identical(back, v)
  }
  # Every bit of NA_real_ and of -0 survives.
  v <- c(NA_real_, neg_zero())
  b <- cbor_encode(v, typed_arrays = TRUE)
  expect_identical(writeBin(cbor_decode(b), raw()), writeBin(v, raw()))
})

test_that("CBOR to R to CBOR is a fixed point for little-endian typed arrays", {
  items <- list(
    typed_item(86, writeBin(c(1, NaN, -0, 3), raw(), endian = "little")),
    typed_item(78, writeBin(c(1L, -1L, 7L), raw(), endian = "little")),
    typed_item(86, writeBin(0.5, raw(), endian = "little")),
    c(hex_raw("d90410 82 82 02 01"), typed_item(78, writeBin(c(4L, 5L), raw(), endian = "little"))),
    c(hex_raw("82 01"), typed_item(86, writeBin(c(2, 3), raw(), endian = "little")))
  )
  for (x in items) expect_identical(cbor_encode(cbor_decode(x), typed_arrays = TRUE), x)
  # Big-endian input decodes to the same value as little-endian input.
  expect_identical(cbor_decode(typed_item(82, writeBin(c(1, 2), raw(), endian = "big"))),
                   cbor_decode(typed_item(86, writeBin(c(1, 2), raw(), endian = "little"))))
})

test_that("typed arrays count toward max_depth as the decoder counts them", {
  expect_error(cbor_encode(list(c(1, 2)), max_depth = 1, typed_arrays = TRUE), class = "zucbor_depth_limit")
  b <- cbor_encode(list(c(1, 2)), max_depth = 2, typed_arrays = TRUE)
  expect_identical(cbor_decode(b, max_depth = 2), list(c(1, 2)))
  expect_error(cbor_decode(b, max_depth = 1), class = "zucbor_depth_limit")
  # A matrix: the tag, its content array, then dimensions and elements.
  expect_error(cbor_encode(matrix(1:4, 2), max_depth = 2, typed_arrays = TRUE), class = "zucbor_depth_limit")
  b <- cbor_encode(matrix(1:4, 2), max_depth = 3, typed_arrays = TRUE)
  expect_identical(cbor_decode(b, max_depth = 3), matrix(1:4, 2))
  expect_error(cbor_decode(b, max_depth = 2), class = "zucbor_depth_limit")
})
