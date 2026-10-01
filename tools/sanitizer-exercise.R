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
  tryCatch(cbor_annotate(x, ...), zucbor_error = function(e) NULL)
  tryCatch(cbor_annotate(x, sequence = TRUE, ...), zucbor_error = function(e) NULL)
  # The build phase, under every mapping option.
  tryCatch(cbor_decode(x, ...), zucbor_error = function(e) NULL)
  tryCatch(cbor_decode_seq(x, simplify = "none", map_keys = "string",
                           tags = "keep", big_integers = "double",
                           duplicate_keys = TRUE, ...),
           zucbor_error = function(e) NULL)
  tryCatch(cbor_decode(x, map_keys = "map", big_integers = "error", ...),
           zucbor_error = function(e) NULL)
  tryCatch(cbor_diagnose(x, sequence = TRUE, duplicate_keys = TRUE, ...),
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

# The encoder: every decoded value encodes, and the result decodes again.
# Hostile R values: deep nesting past the limit, invalid names, bad classes.
for (x in a) {
  v <- tryCatch(cbor_decode(x), zucbor_error = function(e) NULL)
  b <- cbor_encode(v)
  stopifnot(identical(cbor_encode(cbor_decode(b)), b))
  cbor_encode(v, auto_unbox = FALSE, self_describe = TRUE)
}
deep <- 1L
for (i in 1:2000) deep <- list(deep)
for (x in list(deep, list(a = 1, 2), c(a = 1, a = 2), cbor_map(list(1L, 1), list(0, 0)),
               structure("01", class = "cbor_bigint"), structure(20L, class = "cbor_simple"),
               structure(list(tag = -1, value = 1), class = "cbor_tag"), globalenv(), 1i,
               as.POSIXlt("2024-01-01", tz = "UTC"), data.frame(a = 1))) {
  tryCatch(cbor_encode(x), zucbor_error = function(e) NULL)
}
big <- lapply(1:5000, function(i) list(k = i, v = as.character(i)))
invisible(cbor_encode(stats::setNames(big, sprintf("k%05d", sample.int(5000)))))

# Maps at one depth under different parents, with unsorted keys: each
# reuses the entry pool of that depth, which a parent's vmaxset() once
# released (Stage 10). A use after free here is what ASan is for.
inner <- function(i) stats::setNames(as.list(1:40), paste0("k", 40:1, "_", i))
nest <- list(p = list(a = inner(1), b = inner(2)), q = list(c = inner(3), d = inner(4)),
             r = cbor_map(list(cbor_map(list(2L, 1L), list(inner(5), inner(6)))), list(inner(7))))
nb <- cbor_encode(nest)
stopifnot(identical(cbor_encode(cbor_decode(nb)), nb))

# Tag handlers and as_cbor(): user code that returns, errors and nests in
# the middle of the build and the encoder (Stage 10).
h <- list("99" = function(v) v, "24" = function(v) cbor_decode(v, max_depth = 4),
          "37" = function(v) stop("refused"), "0" = function(v) numeric(1e5))
for (x in c(a, list(cbor_encode(list(cbor_tag(99, 1:3), cbor_tag(24, nb), cbor_tag(0, "x")))))) {
  tryCatch(cbor_decode(x, tag_handlers = h), zucbor_error = function(e) NULL)
  tryCatch(cbor_decode_seq(x, tags = "keep", tag_handlers = h), zucbor_error = function(e) NULL)
}
registerS3method("as_cbor", "zu_san", function(x, ...) {
  if (identical(unclass(x), 0L)) stop("refused")
  cbor_tag(24, cbor_encode(list(unclass(x), nest)))
}, envir = asNamespace("zucbor"))
san <- function(v) structure(v, class = "zu_san")
for (x in list(san(1L), list(a = san(2L), b = san(0L)),
               cbor_map(list(san(3L), san(4L)), list(nest, san(5L))))) {
  tryCatch(cbor_encode(x), error = function(e) NULL)
}

# RFC 8746 typed and multi-dimensional arrays (Stage 12): every tag, both
# byte orders, wrong lengths and shapes, then the encoder's typed paths.
for (tag in 64:87) for (len in c(0, 1, 7, 8, 16, 24)) {
  head <- if (tag < 24) as.raw(0xc0 + tag) else as.raw(c(0xd8, tag))
  check(c(head, as.raw(0x40 + len), as.raw(seq_len(len) * 37 %% 256)))
}
for (h in c("d9041082820203d84e5818000000000000000000000000000000000000000000000000",
            "d8288283020203880102030405060708", "d90410828180820102",
            "d904108282 1a80000000 00 80", "d904108282 1bffffffffffffffff 1bffffffffffffffff 80",
            "d90410828102d8565f4800000000000000f04800000000000000f0ff")) {
  check(hex_raw(h))
}
for (v in list(c(1.5, NA, NaN, -0), c(1L, NA), matrix(1:6, 2), array(runif(24), 2:4),
               matrix(list(1L, "a"), 1), matrix(c("a", NA), 1), I(2.5), integer(0))) {
  b <- cbor_encode(v, typed_arrays = TRUE)
  stopifnot(identical(cbor_decode(b), v))
}

cat("sanitizer exercise complete\n")
