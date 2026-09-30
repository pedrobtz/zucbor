# RFC 8949 test vectors, embedded so tests need no network.
#
# Appendix A: cbor/test-vectors appendix_a.json at commit
# aba89b653e484bc8573c22f3ff35641d79dfd8c1, minus f818 (simple(24)): that
# example predates RFC 8949, which removed it as not well-formed (erratum
# 5917; a two-byte simple value below 32 is reserved). It is kept, as a
# must-reject case, in rfc8949_not_well_formed().
#
# Appendix F.1: every example, by category, from
# https://www.rfc-editor.org/rfc/rfc8949.txt. Generated; do not hand-edit.

hex_raw <- function(hex) {
  hex <- gsub("[^0-9a-fA-F]", "", hex)
  if (!nzchar(hex)) return(raw())
  as.raw(strtoi(substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)), 16L))
}

rfc8949_appendix_a <- function() {
  data.frame(
    hex = c("00", "01", "0a", "17", "1818", "1819", "1864", "1903e8",
      "1a000f4240", "1b000000e8d4a51000", "1bffffffffffffffff",
      "c249010000000000000000", "3bffffffffffffffff",
      "c349010000000000000000", "20", "29", "3863", "3903e7", "f90000",
      "f98000", "f93c00", "fb3ff199999999999a", "f93e00", "f97bff",
      "fa47c35000", "fa7f7fffff", "fb7e37e43c8800759c", "f90001", "f90400",
      "f9c400", "fbc010666666666666", "f97c00", "f97e00", "f9fc00",
      "fa7f800000", "fa7fc00000", "faff800000", "fb7ff0000000000000",
      "fb7ff8000000000000", "fbfff0000000000000", "f4", "f5", "f6", "f7",
      "f0", "f8ff", "c074323031332d30332d32315432303a30343a30305a",
      "c11a514b67b0", "c1fb41d452d9ec200000", "d74401020304",
      "d818456449455446",
      "d82076687474703a2f2f7777772e6578616d706c652e636f6d", "40",
      "4401020304", "60", "6161", "6449455446", "62225c", "62c3bc",
      "63e6b0b4", "64f0908591", "80", "83010203", "8301820203820405",
      "98190102030405060708090a0b0c0d0e0f101112131415161718181819", "a0",
      "a201020304", "a26161016162820203", "826161a161626163",
      "a56161614161626142616361436164614461656145", "5f42010243030405ff",
      "7f657374726561646d696e67ff", "9fff", "9f018202039f0405ffff",
      "9f01820203820405ff", "83018202039f0405ff", "83019f0203ff820405",
      "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff",
      "bf61610161629f0203ffff", "826161bf61626163ff",
      "bf6346756ef563416d7421ff"),
    diagnostic = c("0", "1", "10", "23", "24", "25", "100", "1000",
      "1000000", "1000000000000", "18446744073709551615",
      "18446744073709551616", "-18446744073709551616",
      "-18446744073709551617", "-1", "-10", "-100", "-1000", "0.0", "-0.0",
      "1.0", "1.1", "1.5", "65504.0", "100000.0", "3.4028234663852886e+38",
      "1e+300", "5.960464477539063e-08", "6.103515625e-05", "-4.0", "-4.1",
      "Infinity", "NaN", "-Infinity", "Infinity", "NaN", "-Infinity",
      "Infinity", "NaN", "-Infinity", "false", "true", "null", "undefined",
      "simple(16)", "simple(255)", "0(\"2013-03-21T20:04:00Z\")",
      "1(1363896240)", "1(1363896240.5)", "23(h'01020304')",
      "24(h'6449455446')", "32(\"http://www.example.com\")", "h''",
      "h'01020304'", "\"\"", "\"a\"", "\"IETF\"", "\"\\\"\\\\\"", "\"ü\"",
      "\"水\"", "\"𐅑\"", "[]", "[1, 2, 3]", "[1, [2, 3], [4, 5]]",
      "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]",
      "{}", "{1: 2, 3: 4}", "{\"a\": 1, \"b\": [2, 3]}",
      "[\"a\", {\"b\": \"c\"}]",
      "{\"a\": \"A\", \"b\": \"B\", \"c\": \"C\", \"d\": \"D\", \"e\": \"E\"}",
      "(_ h'0102', h'030405')", "\"streaming\"", "[]", "[1, [2, 3], [4, 5]]",
      "[1, [2, 3], [4, 5]]", "[1, [2, 3], [4, 5]]", "[1, [2, 3], [4, 5]]",
      "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]",
      "{\"a\": 1, \"b\": [2, 3]}", "[\"a\", {\"b\": \"c\"}]",
      "{\"Fun\": true, \"Amt\": -2}"),
    roundtrip = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
      TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
      TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
      FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE,
      TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
      TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
      TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,
      FALSE, FALSE),
    stringsAsFactors = FALSE
  )
}

rfc8949_not_well_formed <- function() {
  list(
    end_of_input_in_head = c("18", "19", "1a", "1b", "19 01", "1a 01 02",
      "1b 01 02 03 04 05 06 07", "38", "58", "78", "98", "9a 01 ff 00", "b8",
      "d8", "f8", "f9 00", "fa 00 00", "fb 00 00 00"),
    short_strings = c("41", "61", "5a ff ff ff ff 00",
      "5b ff ff ff ff ff ff ff ff 01 02 03", "7a ff ff ff ff 00",
      "7b 7f ff ff ff ff ff ff ff 01 02 03"),
    short_containers = c("81", "81 81 81 81 81 81 81 81 81", "82 00", "a1",
      "a2 01 02", "a1 00", "a2 00 00 00"),
    tag_without_content = c("c0"),
    unclosed_indefinite_strings = c("5f 41 00", "7f 61 00"),
    unclosed_indefinite_containers = c("9f", "9f 01 02", "bf",
      "bf 01 02 01 02", "81 9f", "9f 80 00", "9f 9f 9f 9f 9f ff ff ff ff",
      "9f 81 9f 81 9f 9f ff ff ff"),
    reserved_additional_information = c("1c", "1d", "1e", "3c", "3d", "3e",
      "5c", "5d", "5e", "7c", "7d", "7e", "9c", "9d", "9e", "bc", "bd", "be",
      "dc", "dd", "de", "fc", "fd", "fe"),
    reserved_two_byte_simple = c("f8 00", "f8 01", "f8 18", "f8 1f"),
    chunk_wrong_type = c("5f 00 ff", "5f 21 ff", "5f 61 00 ff", "5f 80 ff",
      "5f a0 ff", "5f c0 00 ff", "5f e0 ff", "7f 41 00 ff"),
    chunk_not_definite = c("5f 5f 41 00 ff ff", "7f 7f 61 00 ff ff"),
    lone_break = c("ff"),
    break_in_definite = c("81 ff", "82 00 ff", "a1 ff", "a1 ff 00",
      "a1 00 ff", "a2 00 00 ff", "9f 81 ff", "9f 82 9f 81 9f 9f ff ff ff ff"),
    break_in_value_position = c("bf 00 ff", "bf 00 00 00 ff"),
    ai_31_on_int_or_tag = c("1f", "3f", "df"),
    simple_24_in_test_vectors = c("f8 18")
  )
}
