# cbor/test-vectors appendix_a.json, pinned, through an installed zucbor.
#
# Every vector is decoded, re-encoded and printed. A difference from what the
# file expects must be explained by one of the causes below, chosen by rule
# from the vector itself, never by a list of vectors, so that a new
# difference cannot hide in a known cause. Each cause has a baseline count:
# more is a failure (a regression, or a new kind of difference); fewer is
# reported as an improvement. zuxml's W3C harness works the same way.
suppressPackageStartupMessages(library(zucbor))

COMMIT <- "aba89b653e484bc8573c22f3ff35641d79dfd8c1"
url <- sprintf("https://raw.githubusercontent.com/cbor/test-vectors/%s/appendix_a.json", COMMIT)
vectors <- jsonlite::fromJSON(url, simplifyVector = FALSE)

baseline <- c(
  not_well_formed_in_rfc8949 = 1L,   # f818 simple(24): erratum 5917
  whole_float_becomes_integer = 5L,  # design 7.4
  undefined_becomes_null = 1L,       # design 7.4
  tag0_becomes_tag1 = 1L,            # design 7.4: POSIXct encodes as tag 1
  bignum_shown_as_tag = 0L           # the file gives no diagnostic for them
)

hex_raw <- function(h) as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
head_major <- function(x) as.integer(x[1]) %/% 32L
is_whole_float <- function(x) {
  b <- as.integer(x[1])
  b %in% c(0xf9, 0xfa, 0xfb) && {
    v <- cbor_decode(x)
    is.finite(v) && v == trunc(v)
  }
}

causes <- list()
cause <- function(name, hex, what) {
  causes[[length(causes) + 1L]] <<- data.frame(cause = name, hex = hex, what = what)
}
unexplained <- character()

for (v in vectors) {
  h <- v$hex
  x <- hex_raw(h)
  ok <- tryCatch(cbor_validate(x, error = TRUE), error = function(e) e)
  if (inherits(ok, "error")) {
    # RFC 8949 section 3.3: a two-byte simple value below 32 is not well-formed.
    if (length(x) == 2L && x[1] == as.raw(0xf8) && as.integer(x[2]) < 32L &&
        inherits(ok, "zucbor_parse_error")) {
      cause("not_well_formed_in_rfc8949", h, "refused")
    } else {
      unexplained <- c(unexplained, sprintf("%s: refused (%s)", h, class(ok)[1]))
    }
    next
  }
  if (isTRUE(v$roundtrip)) {
    enc <- paste(sprintf("%02x", as.integer(cbor_encode(cbor_decode(x)))), collapse = "")
    if (!identical(enc, h)) {
      if (is_whole_float(x)) cause("whole_float_becomes_integer", h, enc)
      else if (h == "f7") cause("undefined_becomes_null", h, enc)
      else if (x[1] == as.raw(0xc0)) cause("tag0_becomes_tag1", h, enc)
      else unexplained <- c(unexplained, sprintf("%s: re-encodes as %s", h, enc))
    }
  }
  if (!is.null(v$diagnostic)) {
    got <- cbor_diagnose(x)
    if (!identical(got, v$diagnostic)) {
      if (x[1] %in% as.raw(c(0xc2, 0xc3))) cause("bignum_shown_as_tag", h, got)
      else unexplained <- c(unexplained, sprintf("%s: diagnostic %s, file has %s", h, got, v$diagnostic))
    }
  }
}

found <- if (length(causes)) do.call(rbind, causes) else data.frame(cause = character())
counts <- table(factor(found$cause, levels = names(baseline)))
cat(sprintf("==> %d vectors from cbor/test-vectors@%s\n", length(vectors), substr(COMMIT, 1, 8)))
status <- 0L
for (k in names(baseline)) {
  n <- as.integer(counts[[k]])
  flag <- if (n > baseline[[k]]) { status <- 1L; "REGRESSED" } else if (n < baseline[[k]]) "improved" else "ok"
  cat(sprintf("    %-30s %2d (baseline %2d) %s\n", k, n, baseline[[k]], flag))
}
if (length(unexplained)) {
  status <- 1L
  cat("FAIL: unexplained differences:\n", paste0("  ", unexplained, "\n"), sep = "")
}
cat(if (status) "==> conformance FAILED\n" else "==> conformance ok: 0 unexplained\n")
quit(status = status)
