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
  # The build phase, under every mapping option.
  tryCatch(cbor_decode(x, ...), zucbor_error = function(e) NULL)
  tryCatch(cbor_decode_seq(x, simplify = "none", map_keys = "string",
                           tags = "keep", big_integers = "double",
                           duplicate_keys = TRUE, ...),
           zucbor_error = function(e) NULL)
  tryCatch(cbor_decode(x, map_keys = "map", big_integers = "error", ...),
           zucbor_error = function(e) NULL)
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

# Wide integers, bignums at and past the conversion cap, dates.
for (h in c("1b ff ff ff ff ff ff ff ff", "3b ff ff ff ff ff ff ff ff",
            "c2 49 01 00 00 00 00 00 00 00 00", "c3 49 ff ff ff ff ff ff ff ff ff",
            "c0 74 32 30 31 33 2d 30 33 2d 32 31 54 32 30 3a 30 34 3a 30 30 5a",
            "d9 03 ec 6a 32 30 32 34 2d 30 32 2d 32 39", "d8 64 3b ff ff ff ff ff ff ff ff")) {
  check(hex_raw(h))
}
for (n in c(0L, 1L, 8L, 9L, 127L, 128L, 129L, 300L)) {
  payload <- as.raw(sample.int(256, n, replace = TRUE) - 1L)
  check(c(as.raw(0xc3), as.raw(0x58), as.raw(n %% 256L), payload)[if (n < 256) TRUE else -3])
  check(c(as.raw(0xc2), as.raw(c(0x59, n %/% 256L, n %% 256L)), payload))
}

cat("sanitizer exercise complete\n")
