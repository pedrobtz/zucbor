# cbor_annotate(): an annotated hex dump (Stage 13, design section 5).

test_that("every Appendix A example annotates, each byte exactly once", {
  for (h in rfc8949_appendix_a()$hex) {
    r <- annotation_bytes(cbor_annotate(hex_raw(h)))
    expect_identical(r$bytes, h, info = h)
    expect_true(r$offsets_ok, info = h)
  }
})

test_that("every COSE example annotates, each byte exactly once", {
  skip_heavy()
  cose <- utils::read.delim(test_path("fixtures", "cose-wg-examples.tsv"), quote = "",
                            colClasses = "character")
  ok <- vapply(unique(tolower(cose$hex)), function(h) {
    r <- annotation_bytes(cbor_annotate(hex_raw(h)))
    identical(r$bytes, h) && r$offsets_ok
  }, logical(1))
  expect_true(all(ok), info = paste(names(ok)[!ok], collapse = " "))
})

test_that("lines say what each head is", {
  a <- unclass(cbor_annotate(hex_raw("a2 61 61 01 61 62 82 02 03")))
  expect_identical(a, c("0  a2      # map(2)", "1    61    # text(1)", "2      61  # \"a\"",
                        "3    01    # unsigned(1)", "4    61    # text(1)", "5      62  # \"b\"",
                        "6    82    # array(2)", "7      02  # unsigned(2)", "8      03  # unsigned(3)"))
  desc <- function(h) sub("^.*# ", "", unclass(cbor_annotate(hex_raw(h))))
  expect_identical(desc("3901f3"), "negative(-500)")
  expect_identical(desc("3bffffffffffffffff"), "negative(-18446744073709551616)")
  expect_identical(desc("f93e00"), "float16 1.5")
  expect_identical(desc("fa47c35000"), "float32 100000.0")
  expect_identical(desc("fb3ff199999999999a"), "float64 1.1")
  expect_identical(desc("f4"), "false")
  expect_identical(desc("f7"), "undefined")
  expect_identical(desc("f8ff"), "simple(255)")
  expect_identical(desc("c11a514b67b0")[1], "tag(1)")
  expect_identical(desc("5f42010243030405ff"), c("bytes(*)", "bytes(2)", "h'0102'", "bytes(3)", "h'030405'", "break"))
  expect_identical(desc("40"), "bytes(0)")
})

test_that("long strings are rows of 16 bytes, previewed, with bounded output", {
  s <- strrep("é", 40)                            # 80 bytes of UTF-8
  a <- unclass(cbor_annotate(cbor_encode(s)))
  expect_length(a, 1 + 5)
  expect_match(a[2], "# \"(\\\\u00e9){16}\"\\.\\.\\.$")   # 32 bytes, cut at a character
  expect_false(any(grepl("#", a[3:6])))
  big <- cbor_encode(as.raw(rep(0:255, 400)))
  a <- cbor_annotate(big)
  expect_lt(sum(nchar(a)), 5 * length(big))
  expect_identical(annotation_bytes(a)$bytes, paste(format(big), collapse = ""))
})

test_that("a sequence annotates item after item; input is checked first", {
  a <- cbor_annotate(hex_raw("01 61 61"), sequence = TRUE)
  expect_identical(annotation_bytes(a)$bytes, "016161")
  expect_identical(cbor_annotate(raw(), sequence = TRUE), structure(character(), class = "cbor_annotation"))
  expect_output(print(cbor_annotate(raw(), sequence = TRUE)), "empty")
  expect_output(print(cbor_annotate(hex_raw("01"))), "0  01  # unsigned(1)", fixed = TRUE)
  got <- fault_class(list(raw(), hex_raw("8201"), hex_raw("61ff"), hex_raw("0102"), nested(300)),
                     cbor_annotate)
  expect_identical(unname(got), c("zucbor_parse_error", "zucbor_parse_error", "zucbor_invalid_error",
                                  "zucbor_parse_error", "zucbor_depth_limit"))
  expect_error(cbor_annotate(hex_raw("a2 01 00 01 00")), class = "zucbor_duplicate_key")
  expect_error(cbor_annotate("01"), class = "zucbor_invalid_argument")
})

test_that("deep nesting stops indenting at 16 levels", {
  a <- unclass(cbor_annotate(nested(40)))
  indent <- nchar(sub("^ *[0-9]+  ( *).*$", "\\1", a))
  expect_identical(max(indent), 32L)
})
