test_that("an interrupt during a decode unwinds, and the input then decodes", {
  # setTimeLimit() fires from the same R_CheckUserInterrupt() call sites as
  # Ctrl-C, which run every 65,536 items in both phases. Everything they
  # hold is R_alloc()ed or PROTECTed, so the unwind must leave nothing
  # behind (design section 12; zuxml #37 for the technique).
  n <- 4e6
  x <- c(hex_raw("9a"), as.raw(c(n %/% 16777216, (n %/% 65536) %% 256, (n %/% 256) %% 256, n %% 256)),
         rep(as.raw(0x80), n))
  interrupted <- tryCatch({
    setTimeLimit(elapsed = 0.01, transient = TRUE)
    cbor_decode(x, max_items = Inf, max_size = Inf)
    FALSE
  }, error = function(e) TRUE, finally = setTimeLimit())
  expect_true(interrupted)
  v <- cbor_decode(x, max_items = Inf, max_size = Inf)
  expect_length(v, n)
})
