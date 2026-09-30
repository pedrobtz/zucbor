test_that("every status C can report maps to a class", {
  names <- .Call(zucbor:::zucbor_status_names)
  missing <- setdiff(names, names(zucbor:::zu_status_class))
  expect_identical(missing, character())
})

test_that("every class is a zucbor_error", {
  x <- hex_raw("82 01")
  e <- tryCatch(cbor_validate(x, error = TRUE), error = identity)
  expect_s3_class(e, "zucbor_error")
  expect_identical(tail(class(e), 3), c("zucbor_error", "error", "condition"))
})

test_that("a check-phase condition carries its fields", {
  e <- tryCatch(cbor_validate(hex_raw("82 01"), error = TRUE), error = identity)
  expect_named(e, c("message", "call", "offset", "status", "limit", "limit_value"),
               ignore.order = TRUE)
  expect_type(e$offset, "double")
  expect_type(e$status, "character")
  expect_true(is.na(e$limit))
})

test_that("the call is the user's", {
  e <- tryCatch(cbor_validate(hex_raw("82 01"), error = TRUE), error = identity)
  expect_identical(e$call[[1]], quote(cbor_validate))
})

test_that("argument errors name the argument", {
  e <- expect_error(cbor_validate("a1"), class = "zucbor_invalid_argument")
  expect_identical(e$arg, "x")
  for (arg in c("sequence", "deterministic", "duplicate_keys", "error")) {
    args <- list(x = hex_raw("00"))
    args[[arg]] <- NA
    e <- expect_error(do.call(cbor_validate, args), class = "zucbor_invalid_argument")
    expect_identical(e$arg, arg)
  }
})

test_that("failing and succeeding checks interleave cleanly", {
  # Scratch is R_alloc()ed: an error mid-walk must leave nothing behind that
  # a later call could trip over.
  good <- hex_raw("a2 61 61 01 61 62 82 02 03")
  bad <- list(hex_raw("a2 01 00 01 00"), hex_raw("82 01"), c(rep(as.raw(0x81), 300), as.raw(0)))
  for (i in 1:50) {
    for (b in bad) expect_false(cbor_validate(b))
    expect_true(cbor_validate(good))
  }
})
