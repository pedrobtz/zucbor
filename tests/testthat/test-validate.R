test_that("every RFC 8949 Appendix A example validates", {
  a <- rfc8949_appendix_a()
  ok <- vapply(a$hex, function(h) cbor_validate(hex_raw(h)), logical(1))
  expect_true(all(ok), info = paste(a$hex[!ok], collapse = " "))
})

test_that("every RFC 8949 Appendix F example is a parse error", {
  f <- unlist(rfc8949_not_well_formed(), use.names = FALSE)
  got <- fault_class(lapply(f, hex_raw))
  expect_identical(unname(got), rep("zucbor_parse_error", length(f)),
                   info = paste(f[got != "zucbor_parse_error"], collapse = " | "))
  expect_false(any(vapply(f, function(h) cbor_validate(hex_raw(h)), NA)))
})

test_that("every truncation of every Appendix A example is a parse error", {
  a <- rfc8949_appendix_a()
  cuts <- unlist(lapply(a$hex, function(h) {
    bytes <- hex_raw(h)
    lapply(seq_len(length(bytes) - 1L), function(n) bytes[seq_len(n)])
  }), recursive = FALSE)
  expect_length(cuts, 426L)
  got <- fault_class(cuts)
  expect_identical(unname(got), rep("zucbor_parse_error", length(cuts)))
})

test_that("empty input is not an item, but is an empty sequence", {
  e <- expect_error(cbor_validate(raw(), error = TRUE), class = "zucbor_parse_error")
  expect_identical(e$offset, 0)
  expect_true(cbor_validate(raw(), sequence = TRUE))
})

test_that("bytes after the item are refused unless it is a sequence", {
  x <- hex_raw("01 02 03")
  e <- expect_error(cbor_validate(x, error = TRUE), class = "zucbor_parse_error")
  expect_identical(e$status, "CborErrorGarbageAtEnd")
  expect_identical(e$offset, 1)
  expect_true(cbor_validate(x, sequence = TRUE))
})

test_that("a sequence is checked item by item", {
  expect_true(cbor_validate(hex_raw("83 01 02 03 a1 61 61 01 f6"), sequence = TRUE))
  e <- expect_error(cbor_validate(hex_raw("01 83 01"), sequence = TRUE, error = TRUE),
                    class = "zucbor_parse_error")
  expect_identical(e$offset, 1)
})

test_that("invalid UTF-8 in a text string is invalid, not malformed", {
  for (h in c("62 c3 28", "61 ff", "63 ed a0 80", "a1 61 ff 00")) {
    expect_error(cbor_validate(hex_raw(h), error = TRUE),
                 class = "zucbor_invalid_error", info = h)
  }
})

test_that("a known tag with the wrong content type is invalid, with an offset", {
  # tag 0 (date/time text) on an integer; tag 2 (bignum) on text; tag 1 on
  # text; tag 100 (days) on a float; tag 1004 (date text) on an integer; a
  # restricted tag wrapping another tag.
  for (h in c("c0 01", "c2 61 61", "c1 61 61", "d8 64 f9 3c 00", "d9 03 ec 01", "c2 c6 41 01")) {
    e <- expect_error(cbor_validate(hex_raw(h), error = TRUE),
                      class = "zucbor_invalid_error", info = h)
    expect_identical(e$status, "CborErrorInappropriateTagForType")
    expect_identical(e$offset, 0, info = h)
  }
  e <- expect_error(cbor_validate(hex_raw("82 00 c0 01"), error = TRUE), class = "zucbor_invalid_error")
  expect_identical(e$offset, 2)
})

test_that("tag content follows RFC 8949 where TinyCBOR's table does not", {
  # Tag 1 takes an integer or a float (RFC 8949 section 3.4.2); TinyCBOR
  # 7.0 allows only the integer. Tags 21-23 may wrap any item.
  for (h in c("c1 1a 51 4b 67 b0", "c1 fb 41 d4 52 d9 ec 20 00 00", "c1 f9 3c 00",
              "c1 3a 00 01 00 00", "d5 61 61", "d6 01", "d7 f5")) {
    expect_true(cbor_validate(hex_raw(h)), info = h)
  }
})

test_that("an unknown tag with any content is valid", {
  expect_true(cbor_validate(hex_raw("d9 d9 f8 83 01 02 03")))
  expect_true(cbor_validate(hex_raw("da 00 01 00 00 f6")))
})

test_that("faults carry offsets, except deterministic-encoding ones", {
  # UTF-8 is checked by the walk, per chunk, so it has the chunk's offset.
  e <- expect_error(cbor_validate(hex_raw("82 01 61 ff"), error = TRUE), class = "zucbor_invalid_error")
  expect_identical(e$offset, 3)
  expect_identical(e$status, "CborErrorInvalidUtf8TextString")
  e <- expect_error(cbor_validate(hex_raw("82 01"), error = TRUE), class = "zucbor_parse_error")
  expect_false(is.na(e$offset))
  # Deterministic encoding is TinyCBOR's validator, which reports no position.
  e <- expect_error(cbor_validate(hex_raw("18 01"), deterministic = TRUE, error = TRUE),
                    class = "zucbor_deterministic_error")
  expect_true(is.na(e$offset))
})

test_that("each chunk of a text string must be UTF-8 on its own", {
  # U+00FC split across two chunks: c3 | bc (RFC 8949 section 3.2.3).
  expect_false(cbor_validate(hex_raw("7f 61 c3 61 bc ff")))
  expect_true(cbor_validate(hex_raw("7f 62 c3 bc ff")))
})

test_that("error = TRUE returns TRUE invisibly on valid input", {
  expect_invisible(cbor_validate(hex_raw("01"), error = TRUE))
  expect_true(cbor_validate(hex_raw("01"), error = TRUE))
})

test_that("date text that does not parse is invalid, whatever the decoder would do", {
  # RFC 8949 section 3.4.1, RFC 8943: the check owns this (design 6.7).
  t0 <- c(hex_raw("c0 6a"), charToRaw("not a date"))
  d <- c(hex_raw("d9 03 ec 65"), charToRaw("2024x"))
  late <- c(hex_raw("82 01"), t0)                    # the tag at offset 2
  for (x in list(t0, d)) {
    expect_false(cbor_validate(x))
    e <- expect_error(cbor_validate(x, error = TRUE), class = "zucbor_invalid_error")
    expect_identical(e$status, "ZU_ERR_INVALID_DATE")
    expect_identical(e$offset, 0)
    expect_error(cbor_decode(x, tags = "keep"), class = "zucbor_invalid_error")
    expect_error(cbor_decode(x, tag_handlers = list("0" = identity, "1004" = identity)),
                 class = "zucbor_invalid_error")
  }
  e <- expect_error(cbor_validate(late, error = TRUE), class = "zucbor_invalid_error")
  expect_identical(e$offset, 2)
  # Under the self-describe tag, the innermost tag is the one at fault.
  e <- expect_error(cbor_validate(c(hex_raw("d9 d9 f7"), t0), error = TRUE),
                    class = "zucbor_invalid_error")
  expect_identical(e$offset, 3)
  # Chunked text is joined before it is parsed.
  ok <- c(hex_raw("d9 03 ec 7f 64"), charToRaw("2024"), hex_raw("66"), charToRaw("-02-29"), hex_raw("ff"))
  expect_true(cbor_validate(ok))
  expect_identical(cbor_decode(ok), as.Date("2024-02-29"))
})
