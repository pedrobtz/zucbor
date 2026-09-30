# Drives zucbor's C code over hostile and valid input, for the ASan
# containers in native-checks.yaml. Base R only (the images carry no
# testthat), against an installed zucbor. Its value is in the error paths:
# every early return from the walk must leave nothing behind, and every
# TinyCBOR call must see an iterator in the state it expects.
library(zucbor)

source("tests/testthat/helper-rfc8949.R")

check <- function(x, ...) {
  # Any outcome is fine except a crash or a sanitizer report.
  tryCatch(cbor_validate(x, ...), zucbor_error = function(e) FALSE)
  tryCatch(cbor_validate(x, sequence = TRUE, deterministic = TRUE, ...),
           zucbor_error = function(e) FALSE)
}

a <- lapply(rfc8949_appendix_a()$hex, hex_raw)
f <- lapply(unlist(rfc8949_not_well_formed()), hex_raw)

for (x in c(a, f)) {
  check(x)
  for (n in seq_along(x)) check(x[seq_len(n)])
}

# Nesting at and past every limit, through arrays, maps, tags and
# indefinite-length containers.
cap <- zucbor_info()$max_depth_cap
for (byte in c(0x81, 0xa1, 0xc6, 0x9f)) {
  for (n in c(cap - 1L, cap, cap + 1L, 1e5)) {
    x <- c(rep(as.raw(byte), n), as.raw(0x00))
    check(x, max_depth = cap)
  }
}

# Random mutation of valid items: byte flips, insertions and deletions.
set.seed(20260930)
seeds <- a[lengths(a) > 2]
for (i in seq_len(20000)) {
  x <- seeds[[sample.int(length(seeds), 1)]]
  k <- sample.int(3, 1)
  pos <- sample.int(length(x), 1)
  x <- switch(k,
    { x[pos] <- as.raw(sample.int(256, 1) - 1L); x },
    append(x, as.raw(sample.int(256, sample.int(4, 1)) - 1L), after = pos),
    x[-pos]
  )
  check(x, max_items = 64)
}

# Maps with many keys, some duplicated, so the merge sort runs at size.
for (n in c(2L, 3L, 1000L, 4097L)) {
  keys <- unlist(lapply(seq_len(n) %% max(2L, n - 1L), function(i)
    c(as.raw(0x19), as.raw(i %/% 256L), as.raw(i %% 256L), as.raw(0xf6))))
  check(c(as.raw(c(0xb9, n %/% 256L, n %% 256L)), keys))
}

cat("sanitizer exercise complete\n")
