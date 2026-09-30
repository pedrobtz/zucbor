# Benchmarks against design section 17's targets. Not in CI: shared runners
# are too noisy to gate on. Run from the package root with zucbor, zujson
# and bench installed:  Rscript tools/benchmarks.R
#
# Each fixture is one R value, encoded once as JSON (zujson) and once as
# CBOR (zucbor), so both decoders read the same data.
suppressPackageStartupMessages({
  library(zucbor)
  library(zujson)
  library(bench)
})
set.seed(17)

record <- function(i) list(n = paste0("sensor-", i %% 50), t = 1.7e9 + i, v = round(stats::rnorm(1, 20, 5), 3),
                           u = "Cel", ok = i %% 7 != 0)
fixtures <- list(
  "1 KiB message" = list(alg = -7L, kid = "11", payload = strrep("x", 800), claims = list(iss = "coap://as.example.com", exp = 1444064944L)),
  "100 KiB telemetry" = lapply(1:1200, record),
  "10 MiB document" = lapply(1:120000, record),
  "many tiny items" = as.list(seq_len(500000) %% 100L),
  "large strings" = lapply(1:40, function(i) strrep(letters[i %% 26 + 1], 250000))
)

ms <- function(x) as.numeric(x) * 1000
rows <- list()
for (name in names(fixtures)) {
  x <- fixtures[[name]]
  j <- json_write_raw(x)
  b <- cbor_encode(x)
  dec <- mark(json = json_parse_raw(j), cbor = cbor_decode(b, max_items = Inf, max_size = Inf),
              check = FALSE, min_iterations = 5, time_unit = "s")
  enc <- mark(json = json_write_raw(x), cbor = cbor_encode(x),
              check = FALSE, min_iterations = 5, time_unit = "s")
  chk <- mark(cbor_validate(b, max_items = Inf, max_size = Inf), min_iterations = 5, time_unit = "s")
  rows[[name]] <- data.frame(
    fixture = name, json_kb = round(length(j) / 1024), cbor_kb = round(length(b) / 1024),
    decode_json_ms = ms(dec$median[1]), decode_cbor_ms = ms(dec$median[2]),
    encode_json_ms = ms(enc$median[1]), encode_cbor_ms = ms(enc$median[2]),
    check_share = as.numeric(chk$median[1]) / as.numeric(dec$median[2])
  )
}
res <- do.call(rbind, rows)
rownames(res) <- NULL
res$decode_ratio <- res$decode_cbor_ms / res$decode_json_ms
res$encode_ratio <- res$encode_cbor_ms / res$encode_json_ms
print(format(res, digits = 3), row.names = FALSE)
cat("\nTargets (design 17): decode_ratio < 1, encode_ratio < 1, check_share <= 0.30\n")
