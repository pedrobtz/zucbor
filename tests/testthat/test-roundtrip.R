test_that("Appendix A round-trips, apart from the documented lossy conversions", {
  # design section 7.4: whole floats become integers, undefined becomes null,
  # and tag 0 (date text) comes back as tag 1 (epoch).
  lossy <- c("f90000", "f93c00", "f97bff", "fa47c35000", "f9c400", "f7",
             "c074323031332d30332d32315432303a30343a30305a")
  a <- rfc8949_appendix_a()
  for (h in a$hex[a$roundtrip]) {
    enc <- paste(format(cbor_encode(cbor_decode(hex_raw(h)))), collapse = "")
    if (h %in% lossy) {
      expect_false(identical(enc, h), info = h)
    } else {
      expect_identical(enc, h, info = h)
    }
  }
})

test_that("encoding then decoding gives the value back", {
  values <- list(
    1:3, c(1.5, NaN, Inf, -Inf), c("a", NA, "水"), c(TRUE, NA), as.raw(0:255),
    list(a = 1L, b = list(c = "x", d = logical())), list(1L, "a", NULL, I(TRUE)),
    cbor_bigint(c("18446744073709551616", "-9007199254740993")),
    cbor_map(list(1L, "k"), list(-7L, as.raw(1:3))), cbor_tag(6, I(1L)),
    cbor_simple(16), structure(list(), names = character()), logical(),
    as.POSIXct(c(0, 1.5), origin = "1970-01-01", tz = "UTC"),
    as.Date(c("2024-02-29", "1970-01-01"))
  )
  for (v in values) {
    expect_identical(cbor_decode(cbor_encode(v)), v, info = paste(deparse(v), collapse = ""))
  }
  expect_identical(1 / cbor_decode(cbor_encode(neg_zero())), -Inf)
})

test_that("R values that do not survive R -> CBOR -> R are the documented ones", {
  # design section 7.4
  expect_identical(cbor_decode(cbor_encode(list(1L))), I(1L))      # list(1L) -> [1]
  expect_identical(cbor_decode(cbor_encode(list())), logical())    # list() -> []
  expect_identical(cbor_decode(cbor_encode(2)), 2L)                # whole double
  expect_identical(cbor_decode(cbor_encode(NA_real_)), NULL)       # typed NA
})

test_that("every encoding is deterministic and repeatable", {
  set.seed(8949)
  gen <- function(depth) {
    k <- sample.int(if (depth > 3) 6 else 9, 1)
    switch(k,
      sample.int(1e6, 1) - 5e5,
      stats::runif(1) * 10^sample(-5:5, 1),
      paste(sample(letters, sample.int(5, 1)), collapse = ""),
      sample(c(TRUE, FALSE, NA), 1),
      as.raw(sample.int(256, sample.int(5, 1)) - 1L),
      NULL,
      lapply(seq_len(sample.int(4, 1)), function(i) gen(depth + 1)),
      stats::setNames(lapply(1:3, function(i) gen(depth + 1)), sample(letters, 3)),
      cbor_map(list(sample.int(100, 1), paste0("k", sample.int(100, 1))),
               list(gen(depth + 1), gen(depth + 1)))
    )
  }
  ok <- vapply(1:300, function(i) {
    v <- gen(0)
    a <- cbor_encode(v)
    identical(cbor_encode(v), a) &&                  # repeatable
      cbor_validate(a, deterministic = TRUE) &&      # deterministic
      identical(cbor_encode(cbor_decode(a)), a)      # decode -> encode is a fixed point
  }, NA)
  expect_true(all(ok), info = paste(which(!ok), collapse = " "))
})

test_that("every cbor_tag either encodes deterministically or is refused", {
  # design section 8 and section 20, criterion 5: random content under the
  # tags whose content is restricted, built directly and by as_cbor().
  local_as_cbor("zu_test_tagged", function(x, ...) cbor_tag(attr(x, "tag"), unclass(x)[[1]]))
  set.seed(8746)
  tags <- c(0, 1, 2, 3, 4, 18, 24, 32, 40, 64, 65, 85, 100, 1004, 1040, 6, 55799)
  contents <- list(
    function() sample.int(1e6, 1) - 5e5,
    function() stats::runif(1),
    function() "x",
    function() "2024-02-29",
    function() "2013-03-21T20:04:00Z",
    function() as.raw(sample.int(256, sample.int(12, 1)) - 1L),
    function() as.raw(c(0, sample.int(256, sample.int(12, 1)) - 1L)),
    function() raw(),
    function() list(1L, "a"),
    function() list(c(2L, 2L), 1:4),
    function() list(c(2L, 2L), 1:3),
    function() list(I(2L), cbor_tag(64, as.raw(1:2))),
    function() NULL,
    function() cbor_tag(6, 1L)
  )
  outcome <- vapply(1:600, function(i) {
    v <- cbor_tag(sample(tags, 1), contents[[sample.int(length(contents), 1)]]())
    if (i %% 2 == 0) v <- structure(list(v$value), tag = v$tag, class = "zu_test_tagged")
    if (i %% 3 == 0) v <- list(v, 1L)
    a <- tryCatch(cbor_encode(v), zucbor_invalid_argument = function(e) NULL)
    if (is.null(a)) return("refused")
    if (identical(cbor_encode(v), a) && cbor_validate(a, deterministic = TRUE)) "ok" else "bad"
  }, "")
  expect_false(any(outcome == "bad"), info = paste(which(outcome == "bad"), collapse = " "))
  expect_true(all(c("ok", "refused") %in% outcome))
})
