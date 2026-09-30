# Writes the fuzz seed corpus into a directory (default fuzz/seeds, not
# committed): every embedded RFC 8949 vector, the conformance fixtures, and
# a few hostile shapes. Each seed is prefixed with an option byte, which
# fuzz_check.c reads first. Run from the package root.
args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[[1]] else file.path("fuzz", "seeds")
dir.create(out, showWarnings = FALSE, recursive = TRUE)
source(file.path("tests", "testthat", "helper-rfc8949.R"))

fx <- file.path("tests", "testthat", "fixtures")
qcbor <- readLines(file.path(fx, "qcbor-not-well-formed.txt"))
cose <- utils::read.delim(file.path(fx, "cose-wg-examples.tsv"), quote = "", colClasses = "character")
spec <- utils::read.delim(file.path(fx, "spec-examples.tsv"), quote = "", colClasses = "character")
hex <- c(rfc8949_appendix_a()$hex, unlist(rfc8949_not_well_formed()),
         qcbor[!startsWith(qcbor, "#")], cose$hex, spec$hex,
         "9f9f9f9f9f9f9f9fffffffffffffffff", "a3616101616201616101",
         "c2490100000000000000ff", "5f41004101ff", "bf616100ff")
hex <- unique(gsub(" ", "", hex))
n <- 0L
for (h in hex) {
  bytes <- hex_raw(h)
  for (opt in if (length(bytes) < 64) c(0x00, 0x02, 0x19) else 0x00) {
    n <- n + 1L
    writeBin(c(as.raw(opt), bytes), file.path(out, sprintf("seed-%04d", n)))
  }
}
cat(n, "seeds written to", out, "\n")
