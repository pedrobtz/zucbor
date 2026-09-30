test_that("duplicate keys are refused by default and accepted on request", {
  x <- hex_raw("a2 01 00 01 00")        # {1: 0, 1: 0}
  expect_false(cbor_validate(x))
  expect_true(cbor_validate(x, duplicate_keys = TRUE))
})

test_that("the offset is the second occurrence", {
  e <- dup_error("a3 61 61 00 61 62 00 61 61 00")   # {"a": 0, "b": 0, "a": 0}
  expect_identical(e$offset, 7)
  expect_identical(e$status, "ZU_ERR_DUPLICATE_KEY")
})

test_that("integers are compared by value, whatever their width", {
  dup_error("a2 01 00 18 01 00")                    # 1 and 1 in two bytes
  dup_error("a2 01 00 1b 00 00 00 00 00 00 00 01 00")
  dup_error("a2 20 00 38 00 00")                    # -1 twice
  expect_true(cbor_validate(hex_raw("a2 01 00 21 00")))   # 1 and -2
  expect_true(cbor_validate(hex_raw("a2 00 00 20 00")))   # 0 and -1
})

test_that("strings are compared by content, chunked or not", {
  dup_error("a2 61 61 00 7f 61 61 ff 00")           # "a" and (_ "a")
  dup_error("a2 62 61 62 00 7f 61 61 61 62 ff 00")  # "ab" and (_ "a", "b")
  dup_error("a2 41 01 00 5f 41 01 ff 00")           # h'01' twice
  expect_true(cbor_validate(hex_raw("a2 61 61 00 41 61 00")))   # "a" and h'61'
  expect_true(cbor_validate(hex_raw("a2 61 61 00 62 61 61 00")))
  expect_true(cbor_validate(hex_raw("a2 60 00 40 00")))         # "" and h''
})

test_that("floats are compared by value, whatever their width", {
  dup_error("a2 f9 3c 00 00 fb 3f f0 00 00 00 00 00 00 00")      # 1.0 half and double
  dup_error("a2 fa 3f c0 00 00 00 f9 3e 00 00")                  # 1.5 single and half
  dup_error("a2 f9 7e 00 00 fb 7f f8 00 00 00 00 00 01 00")      # NaN and NaN
  expect_true(cbor_validate(hex_raw("a2 f9 00 00 00 f9 80 00 00")))   # 0.0 and -0.0
  expect_true(cbor_validate(hex_raw("a2 01 00 f9 3c 00 00")))         # 1 and 1.0
})

test_that("simple values, booleans, null and undefined are distinct keys", {
  dup_error("a2 f5 00 f5 00")
  dup_error("a2 f6 00 f6 00")
  dup_error("a2 f0 00 f0 00")
  expect_true(cbor_validate(hex_raw("a4 f4 00 f5 00 f6 00 f7 00")))
})

test_that("array, map and tagged keys are compared by their encoding", {
  dup_error("a2 82 01 02 00 82 01 02 00")
  dup_error("a2 a1 01 02 00 a1 01 02 00")
  dup_error("a2 c1 00 00 c1 00 00")
  expect_true(cbor_validate(hex_raw("a2 82 01 02 00 82 02 01 00")))
  expect_true(cbor_validate(hex_raw("a2 c1 00 00 c1 01 00")))
  # Equal in value, encoded differently: not detected. deterministic = TRUE
  # refuses the longer encoding instead (design section 6.5).
  x <- hex_raw("a2 81 01 00 81 18 01 00")
  expect_true(cbor_validate(x))
  expect_error(cbor_validate(x, deterministic = TRUE, error = TRUE),
               class = "zucbor_deterministic_error")
})

test_that("keys are checked per map, including nested maps", {
  expect_true(cbor_validate(hex_raw("a2 01 a1 01 00 02 a1 01 00")))  # {1: {1: 0}, 2: {1: 0}}
  dup_error("a1 01 a2 02 00 02 00")                                   # {1: {2: 0, 2: 0}}
  dup_error("a2 01 a1 02 00 01 00")                                   # outer 1 twice
  dup_error("81 a2 61 78 00 61 78 00")                                # inside an array
})

test_that("a map with many keys is checked in n log n", {
  n <- 20000L
  keys <- lapply(seq_len(n) - 1L, function(i) c(as.raw(0x19), as.raw(i %/% 256L), as.raw(i %% 256L), as.raw(0x00)))
  body <- unlist(keys)
  x <- c(as.raw(c(0xb9, n %/% 256L, n %% 256L)), body)
  expect_true(cbor_validate(x))
  x2 <- c(as.raw(c(0xb9, n %/% 256L, n %% 256L)), body[-(1:4)], as.raw(c(0x19, 0x00, 0x05, 0x00)))
  expect_false(cbor_validate(x2))
})
