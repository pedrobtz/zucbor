# cbor_read_seq(each =): roadmap Stage 15, design section 9.

test_that("each item is passed to each, and the count is returned", {
  path <- withr::local_tempfile(fileext = ".cbor")
  items <- list(1L, "two", I(3L), NULL, list(a = TRUE), as.raw(1:3))
  writeBin(cbor_encode_seq(items), path)
  got <- list()
  n <- cbor_read_seq(path, each = function(item) got[length(got) + 1L] <<- list(item))
  expect_identical(n, 6)
  expect_identical(got, items)
  expect_identical(got, cbor_read_seq(path))
})

test_that("an empty input calls each never and returns 0", {
  calls <- 0
  con <- rawConnection(raw())
  on.exit(close(con))
  expect_identical(cbor_read_seq(con, each = function(item) calls <<- calls + 1), 0)
  expect_identical(calls, 0)
})

test_that("every truncation of every Appendix A item is truncation, not a fault", {
  # The stage's real work: an input that ends inside an item asks for more,
  # whatever the item and wherever the cut.
  a <- rfc8949_appendix_a()
  bad <- character()
  for (h in a$hex) {
    x <- hex_raw(h)
    for (cut in seq_len(length(x) - 1L)) {
      r <- stream_check(c(hex_raw("00"), x[seq_len(cut)]))
      if (!is.null(r[[1L]]) || r[[3L]] != 1 || length(r[[2L]]) != 1L) {
        bad <- c(bad, paste0(h, "@", cut))
      }
    }
  }
  expect_identical(bad, character())
})

test_that("Appendix A read in pieces decodes as a sequence does", {
  a <- rfc8949_appendix_a()
  x <- unlist(lapply(a$hex, hex_raw))
  want <- cbor_decode_seq(x)
  for (block in c(1, 2, 3, 7)) {
    expect_identical(read_each(x, block = block), want, info = block)
  }
})

test_that("a not-well-formed item fails as cbor_decode_seq() fails, at its offset", {
  f <- unlist(rfc8949_not_well_formed(), use.names = FALSE)
  lead <- hex_raw("83 01 02 03 61 61")
  fault <- function(g) tryCatch({g(); "ok"}, error = function(e) {
    paste(class(e)[1], format(e$offset))
  })
  want <- vapply(f, function(h) fault(function() cbor_decode_seq(c(lead, hex_raw(h)))), "")
  got <- vapply(f, function(h) fault(function() read_each(c(lead, hex_raw(h)), block = 1)), "")
  expect_identical(got, want)
  expect_false(any(want == "ok"))
})

test_that("a faulty item stops the read after the items before it", {
  x <- c(cbor_encode_seq(list(1L, 2L, 3L)), hex_raw("62 c3 28"), cbor_encode(4L))
  seen <- integer()
  e <- expect_error(cbor_read_seq(local_raw_con(x), each = function(i) seen <<- c(seen, i)),
                    class = "zucbor_invalid_error")
  expect_identical(seen, 1:3)
  expect_identical(e$offset, 4)
})

test_that("input ending inside an item is a parse error after the items before it", {
  seen <- 0
  x <- c(cbor_encode_seq(list(1L, 2L)), hex_raw("83 01 02"))
  e <- expect_error(read_each(x, block = 1), class = "zucbor_parse_error")
  expect_identical(e$offset, 5)
  expect_error(cbor_read_seq(local_raw_con(x), each = function(i) seen <<- seen + 1),
               class = "zucbor_parse_error")
  expect_identical(seen, 2)
})

test_that("max_size bounds an item, not the stream", {
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(rep(cbor_encode(as.list(1:20)), 100), path)  # 100 items of 21 bytes
  n <- cbor_read_seq(path, each = function(i) NULL, max_size = 21)
  expect_identical(n, 100)
  expect_error(cbor_read_seq(path, max_size = 21), class = "zucbor_size_limit")

  writeBin(c(cbor_encode(1L), cbor_encode(as.list(1:30))), path)  # then 39 bytes
  e <- expect_error(cbor_read_seq(path, each = function(i) NULL, max_size = 21),
                    class = "zucbor_size_limit")
  expect_identical(e$offset, 1)
  expect_identical(e$limit_value, 21)
})

test_that("a length header past max_size is refused without reading on", {
  # A 2^64-byte string head, then an endless supply of bytes.
  con <- rawConnection(c(hex_raw("5b ff ff ff ff ff ff ff ff"), raw(1e5)))
  on.exit(close(con))
  expect_error(cbor_read_seq(con, each = function(i) NULL, max_size = 1000),
               class = "zucbor_size_limit")
  expect_identical(seek(con), 1000)
})

test_that("max_items applies to each item", {
  x <- rep(cbor_encode(1:3), 4)
  expect_identical(cbor_read_seq(local_raw_con(x), each = function(i) NULL, max_items = 4), 4)
  expect_error(cbor_read_seq(local_raw_con(x), max_items = 4), class = "zucbor_item_limit")
  expect_error(cbor_read_seq(local_raw_con(x), each = function(i) NULL, max_items = 3),
               class = "zucbor_item_limit")
})

test_that("the decoding arguments apply, tag handlers included", {
  x <- cbor_encode_seq(list(cbor_map(list(1L), list(cbor_tag(99, 2L))), 5L))
  got <- read_each(x, map_keys = "string", tag_handlers = list("99" = function(v) v * 2L))
  expect_identical(got, list(list("1" = 4L), 5L))
  dup <- hex_raw("a2 61 61 01 61 61 02")
  expect_error(read_each(dup), class = "zucbor_duplicate_key")
  expect_identical(read_each(dup, duplicate_keys = TRUE), cbor_decode_seq(dup, duplicate_keys = TRUE))
  expect_error(read_each(hex_raw("fa 3f 80 00 00"), deterministic = TRUE),
               class = "zucbor_deterministic_error")
})

test_that("an error in each propagates unchanged and closes the connection", {
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(cbor_encode_seq(list(1L, 2L, 3L)), path)
  con <- file(path)
  e <- expect_error(cbor_read_seq(con, each = function(i) if (i == 2L) stop("no twos")),
                    "no twos")
  expect_false(inherits(e, "zucbor_error"))
  expect_error(isOpen(con))
})

test_that("bad arguments are refused", {
  x <- rawConnection(cbor_encode(1L))
  on.exit(close(x))
  expect_error(cbor_read_seq(x, each = "print"), class = "zucbor_invalid_argument")
  expect_error(cbor_read_seq(x, each = print, max_size = 0), class = "zucbor_invalid_argument")
  expect_error(cbor_read_seq(x, each = print, max_items = -1), class = "zucbor_invalid_argument")
  expect_error(cbor_read_seq(x, each = print, simplify = "no"), class = "zucbor_invalid_argument")
})

test_that("10^6 items are read in memory bounded by the largest item", {
  skip_on_cran()
  skip_heavy()
  # max_size = 256 caps the buffer at 256 bytes, so the reader cannot hold
  # more than one 9-byte item and part of the next few: the stream is 9 MB.
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(rep(cbor_encode(2^40), 1e6), path)
  total <- 0
  n <- cbor_read_seq(path, each = function(i) total <<- total + i, max_size = 256)
  expect_identical(n, 1e6)
  expect_identical(total, 1e6 * 2^40)
})

test_that("an interrupt during the read unwinds and closes the connection", {
  skip_heavy()
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(rep(cbor_encode(1L), 2e5), path)
  con <- file(path)
  # The limit fires in the sleep, mid-stream, however fast the machine.
  seen <- 0
  interrupted <- tryCatch({
    setTimeLimit(elapsed = 0.05, transient = TRUE)
    cbor_read_seq(con, max_size = 16, each = function(i) {
      seen <<- seen + 1
      if (seen == 1e5) Sys.sleep(1)
    })
    FALSE
  }, error = function(e) TRUE, finally = setTimeLimit())
  expect_true(interrupted)
  expect_lte(seen, 1e5)
  expect_error(isOpen(con))
  expect_identical(cbor_read_seq(path, each = function(i) NULL), 2e5)
})
