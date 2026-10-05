test_that("cbor_read() reads a file path", {
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(hex_raw("a1 61 61 01"), path)
  expect_identical(cbor_read(path), list(a = 1L))
  expect_identical(cbor_read(path, map_keys = "map"), cbor_map(list("a"), list(1L)))
})

test_that("cbor_read_seq() reads a sequence", {
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(hex_raw("01 02 03"), path)
  expect_identical(cbor_read_seq(path), list(1L, 2L, 3L))
  expect_error(cbor_read(path), class = "zucbor_parse_error")
})

test_that("an unopened connection is opened and closed", {
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(hex_raw("83 01 02 03"), path)
  con <- file(path)
  expect_identical(cbor_read(con), 1:3)
  # close() destroys an R connection, so it is gone, not merely closed.
  expect_error(isOpen(con))
})

test_that("an open connection is read from where it is and left open", {
  con <- rawConnection(hex_raw("ff 83 01 02 03"))
  on.exit(close(con))
  readBin(con, "raw", n = 1)
  expect_identical(cbor_read(con), 1:3)
  expect_true(isOpen(con))
})

test_that("no more than max_size + 1 bytes are read", {
  con <- rawConnection(rep(as.raw(0x01), 1e6))
  on.exit(close(con))
  e <- expect_error(cbor_read(con, max_size = 1000), class = "zucbor_size_limit")
  expect_identical(e$limit_value, 1000)
  expect_identical(seek(con), 1001)
})

test_that("a file one byte over the limit is refused, one at it is read", {
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(c(hex_raw("58 0a"), as.raw(1:10)), path)
  expect_identical(cbor_read(path, max_size = 12), as.raw(1:10))
  expect_error(cbor_read(path, max_size = 11), class = "zucbor_size_limit")
})

test_that("bad paths are argument errors", {
  expect_error(cbor_read(file.path(tempdir(), "no-such-file.cbor")), class = "zucbor_invalid_argument")
  expect_error(cbor_read(tempdir()), class = "zucbor_invalid_argument")
  expect_error(cbor_read(NA_character_), class = "zucbor_invalid_argument")
  expect_error(cbor_read(c("a", "b")), class = "zucbor_invalid_argument")
})

test_that("an open text-mode connection is refused", {
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(hex_raw("01"), path)
  con <- file(path, "r")
  on.exit(close(con))
  expect_error(cbor_read(con), class = "zucbor_invalid_argument")
})

test_that("a connection that cannot be read is an I/O error", {
  path <- withr::local_tempfile(fileext = ".cbor")
  for (read in list(cbor_read, cbor_read_seq, function(con) cbor_read_seq(con, each = identity))) {
    con <- file(path, "wb")
    e <- expect_error(read(con), class = "zucbor_io_error")
    close(con)
    expect_s3_class(e, "zucbor_error")
  }
})
