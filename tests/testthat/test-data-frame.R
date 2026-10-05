# Data frames: roadmap Stage 14, design sections 6.10 and 7.7.

test_that("a data frame encodes as an array of one map per row", {
  df <- data.frame(b = c(1L, NA), a = c("x", "y"))
  expect_cbor(df, "82 a2 61 61 61 78 61 62 01 a2 61 61 61 79 61 62 f6")
  rownames(df) <- c("r1", "r2")
  expect_cbor(df, "82 a2 61 61 61 78 61 62 01 a2 61 61 61 79 61 62 f6")
})

test_that("each cell follows the ordinary mapping", {
  df <- data.frame(
    d = c(1.5, 2), f = factor(c("lo", "hi")), t = as.Date(c("2024-01-01", NA)),
    l = c(TRUE, NA)
  )
  df$list <- list(1:2, NULL)
  expect_identical(
    cbor_decode(cbor_encode(df)),
    list(
      list(d = 1.5, f = "lo", l = TRUE, t = as.Date("2024-01-01"), list = 1:2),
      list(d = 2L, f = "hi", l = NULL, t = NULL, list = NULL)
    )
  )
})

test_that("empty frames encode as empty arrays and maps", {
  expect_cbor(data.frame(a = integer()), "80")
  expect_cbor(data.frame(row.names = 1:2), "82 a0 a0")
  expect_cbor(data.frame(), "80")
})

test_that("a subclass of data.frame encodes as a data frame", {
  df <- structure(list(a = 1:2), class = c("tbl_df", "tbl", "data.frame"),
                  row.names = c(NA, -2L))
  expect_identical(cbor_encode(df), cbor_encode(data.frame(a = 1:2)))
})

test_that("a column of a class with an as_cbor() method is converted whole", {
  local_as_cbor("zu_test_id", function(x, ...) paste0("id-", unclass(x)))
  df <- data.frame(n = 1:2)
  df$id <- structure(3:4, class = "zu_test_id")
  # Keys are in deterministic order: shorter first, so "n" before "id".
  expect_identical(cbor_decode(cbor_encode(df), data_frame = TRUE),
                   data.frame(n = 1:2, id = c("id-3", "id-4")))
})

test_that("frames that cannot be written are refused", {
  m <- data.frame(a = 1:2)
  m$m <- matrix(1:4, 2)
  expect_error(cbor_encode(m), class = "zucbor_unsupported_type")
  nested <- data.frame(a = 1:2)
  nested$d <- data.frame(x = 1:2)
  expect_error(cbor_encode(nested), class = "zucbor_unsupported_type")
  expect_error(cbor_encode(data.frame(r = as.raw(1:2))), class = "zucbor_unsupported_type")
  dup <- data.frame(a = 1, a = 2, check.names = FALSE)
  expect_error(cbor_encode(dup), class = "zucbor_duplicate_key")
  blank <- data.frame(a = 1, b = 2)
  names(blank) <- c("a", "")
  expect_error(cbor_encode(blank), class = "zucbor_invalid_argument")
  local_as_cbor("zu_test_bad", function(x, ...) function() NULL)
  bad <- data.frame(n = 1:2)
  bad$x <- structure(1:2, class = "zu_test_bad")
  expect_error(cbor_encode(bad), class = "zucbor_invalid_argument")
})

test_that("depth is charged for the array and its row maps", {
  df <- data.frame(a = 1:2)
  expect_error(cbor_encode(df, max_depth = 1), class = "zucbor_depth_limit")
  expect_identical(length(cbor_encode(df, max_depth = 2)), 9L)
  expect_identical(cbor_encode(data.frame(a = integer()), max_depth = 1), hex_raw("80"))
})

test_that("decoding makes data frames only when asked", {
  x <- hex_raw("82 a1 61 61 01 a1 61 61 02")
  expect_identical(cbor_decode(x), list(list(a = 1L), list(a = 2L)))
  expect_identical(cbor_decode(x, data_frame = TRUE), data.frame(a = 1:2))
})

test_that("columns are the union of keys in first-seen order, missing as NA", {
  x <- cbor_encode(list(list(b = 1L), list(a = "x"), list(b = 2.5, c = TRUE)))
  want <- data.frame(b = c(1, NA, 2.5), a = c(NA, "x", NA), c = c(NA, NA, TRUE))
  expect_identical(cbor_decode(x, data_frame = TRUE), want)
})

test_that("each column simplifies by the array lattice", {
  x <- cbor_encode(list(
    list(i = 1L, n = 1L, s = "a", m = 1L, b = TRUE, w = cbor_bigint("18446744073709551615")),
    list(i = 2L, n = 1.5, s = NULL, m = "a", b = NULL, w = 2^40)
  ))
  df <- cbor_decode(x, data_frame = TRUE)
  expect_identical(df$i, 1:2)
  expect_identical(df$n, c(1, 1.5))
  expect_identical(df$s, c("a", NA))
  expect_identical(df$m, list(1L, "a"))
  expect_identical(df$b, c(TRUE, NA))
  expect_identical(df$w, cbor_bigint(c("18446744073709551615", "1099511627776")))
  # A float and a wide integer do not combine, though both are doubles in R.
  y <- cbor_encode(list(list(w = cbor_bigint("18446744073709551615")), list(w = 1.5)))
  expect_type(cbor_decode(y, data_frame = TRUE)$w, "list")
  # A cell that is itself an array or a map makes a list column.
  z <- cbor_encode(list(list(a = 1:2), list(a = list(k = 1L))))
  expect_identical(cbor_decode(z, data_frame = TRUE)$a, list(1:2, list(k = 1L)))
  # simplify = "none" leaves every column a list; a missing cell is NULL.
  v <- cbor_decode(cbor_encode(list(list(a = 1L), list(b = 2L))), data_frame = TRUE,
                   simplify = "none")
  expect_identical(v$a, list(1L, NULL))
})

test_that("only arrays of text-keyed maps become data frames", {
  keep <- list(
    "80",                                   # []
    "82 a1 61 61 01 f6",                    # a null among the rows
    "82 a1 61 61 01 01",                    # a number among them
    "82 a1 61 61 01 a1 01 02",              # an integer key
    "82 a1 61 61 01 a1 60 02",              # an empty text key
    "81 c1 01"                              # no maps at all
  )
  for (h in keep) {
    x <- hex_raw(h)
    expect_identical(cbor_decode(x, data_frame = TRUE), cbor_decode(x), info = h)
  }
  # Duplicate keys, when allowed, make a cbor_map, which is not a row.
  d <- hex_raw("81 a2 61 61 01 61 61 02")
  expect_s3_class(cbor_decode(d, data_frame = TRUE, duplicate_keys = TRUE)[[1]], "cbor_map")
  # Nor is a map with an empty key under map_keys = "string" (design 6.10).
  empty <- hex_raw("81 a1 60 01")
  expect_identical(cbor_decode(empty, data_frame = TRUE, map_keys = "string"),
                   cbor_decode(empty, map_keys = "string"))
  # Stringified keys are not text keys.
  s <- hex_raw("81 a1 01 02")
  expect_identical(cbor_decode(s, data_frame = TRUE, map_keys = "string"), list(list("1" = 2L)))
  # A map under the self-describe tag is still a row.
  t <- hex_raw("81 d9 d9 f7 a1 61 61 01")
  expect_identical(cbor_decode(t, data_frame = TRUE), data.frame(a = 1L))
})

test_that("frames nest, and a multi-dimensional array of maps stays an array", {
  x <- cbor_encode(list(rows = list(list(a = 1L), list(a = 2L)), n = 2L))
  expect_identical(cbor_decode(x, data_frame = TRUE),
                   list(n = 2L, rows = data.frame(a = 1:2)))
  m <- cbor_encode(cbor_tag(1040, list(c(2L, 1L), list(list(a = 1L), list(a = 2L)))))
  got <- cbor_decode(m, data_frame = TRUE)
  expect_identical(dim(got), c(2L, 1L))
  expect_identical(got[[2]], list(a = 2L))
})

test_that("data frames round-trip apart from the documented losses", {
  df <- data.frame(
    id = 1:3, name = c("a", NA, "c"), score = c(1.5, 2, NA), ok = c(TRUE, FALSE, NA),
    day = as.Date("2024-01-01") + 0:2,
    when = as.POSIXct(c(0, 1.5, NA), origin = "1970-01-01", tz = "UTC"),
    f = factor(c("x", "y", "x"))
  )
  df$list <- list(1:2, "z", NULL)
  got <- cbor_decode(cbor_encode(df), data_frame = TRUE)
  # Columns come back in the encoded key order; factors as their labels.
  want <- df
  want$f <- as.character(want$f)
  want$list <- list(1:2, "z", NULL)
  want <- want[order(nchar(names(want)), names(want))]
  expect_identical(got, want)
  # Re-encoding what was decoded gives the same bytes.
  expect_identical(cbor_encode(got), cbor_encode(df))
})

test_that("max_cells refuses a quadratic frame before allocating it", {
  # 5000 rows sharing no keys: 25 million cells from 50 kB.
  rows <- lapply(seq_len(5000), function(i) setNames(list(i), paste0("k", i)))
  x <- cbor_encode(rows)
  e <- expect_error(cbor_decode(x, data_frame = TRUE), class = "zucbor_cell_limit")
  expect_s3_class(e, "zucbor_limit_error")
  expect_identical(e$limit, "max_cells")
  expect_identical(e$limit_value, 1e7)
  expect_identical(e$offset, 0)
  # The limit is on rows times columns, inclusive.
  y <- cbor_encode(list(list(a = 1L, b = 2L), list(c = 3L)))
  expect_s3_class(cbor_decode(y, data_frame = TRUE, max_cells = 6), "data.frame")
  expect_error(cbor_decode(y, data_frame = TRUE, max_cells = 5), class = "zucbor_cell_limit")
  # Off unless data_frame = TRUE.
  expect_type(cbor_decode(y, max_cells = 1), "list")
})

test_that("bad data frame arguments are refused", {
  x <- hex_raw("80")
  for (bad in list(NA, "yes", c(TRUE, FALSE), 1)) {
    expect_error(cbor_decode(x, data_frame = bad), class = "zucbor_invalid_argument")
  }
  for (bad in list(0, -1, 1.5, NA, "1", c(1, 2))) {
    expect_error(cbor_decode(x, max_cells = bad), class = "zucbor_invalid_argument")
  }
  expect_identical(cbor_decode(x, data_frame = TRUE, max_cells = Inf), logical(0))
})

test_that("every decoder takes data_frame", {
  x <- cbor_encode(list(list(a = 1L), list(a = 2L)))
  want <- data.frame(a = 1:2)
  expect_identical(cbor_decode_seq(c(x, x), data_frame = TRUE), list(want, want))
  expect_identical(cbor_decode_prefix(c(x, as.raw(0xff)), data_frame = TRUE)$value, want)
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(x, path)
  expect_identical(cbor_read(path, data_frame = TRUE), want)
  got <- list()
  cbor_read_seq(path, data_frame = TRUE, each = function(i) got[[length(got) + 1L]] <<- i)
  expect_identical(got, list(want))
})

test_that("a SenML pack decodes to a frame", {
  # RFC 8428 section 5.1.2's example, with its text labels (bn and bt are
  # the base name and base time).
  pack <- list(
    list(bn = "urn:dev:ow:10e2073a01080063:", bt = 1.320067464e9, n = "voltage", u = "V", v = 120.1),
    list(n = "current", t = -5L, v = 1.2),
    list(n = "current", t = -4L, v = 1.3)
  )
  df <- cbor_decode(cbor_encode(pack), data_frame = TRUE)
  expect_identical(nrow(df), 3L)
  expect_identical(df$n, c("voltage", "current", "current"))
  expect_identical(df$t, c(NA, -5L, -4L))
  expect_identical(df$bn, c("urn:dev:ow:10e2073a01080063:", NA, NA))
})
