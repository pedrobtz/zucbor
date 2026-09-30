# Third-party test data (fixtures/README.md). Each block reads its fixture
# inside the block, so the file stays shuffle-safe.

test_that("every QCBOR not-well-formed vector is refused as not well-formed", {
  v <- readLines(test_path("fixtures", "qcbor-not-well-formed.txt"))
  v <- v[!startsWith(v, "#")]
  expect_length(v, 122L)
  x <- lapply(v, hex_raw)
  got <- fault_class(x)
  expect_identical(unname(got), rep("zucbor_parse_error", 122L), info = paste(v[got != "zucbor_parse_error"], collapse = " | "))
  got <- fault_class(x, cbor_decode)
  expect_identical(unname(got), rep("zucbor_parse_error", 122L))
})

test_that("every cose-wg example is valid, and deterministic ones round-trip exactly", {
  cose <- utils::read.delim(test_path("fixtures", "cose-wg-examples.tsv"), quote = "",
                            colClasses = "character", na.strings = character())
  expect_identical(nrow(cose), 651L)
  expect_identical(as.vector(table(cose$kind)[c("output", "ToBeSign_hex", "ToMac_hex", "AAD_hex")]),
                   c(306L, 86L, 88L, 171L))
  x <- lapply(cose$hex, hex_raw)
  valid <- vapply(x, cbor_validate, NA)
  expect_true(all(valid), info = paste(cose$file[!valid], collapse = " | "))
  determ <- vapply(x, cbor_validate, NA, deterministic = TRUE)
  rt <- vapply(x, function(b) identical(cbor_encode(cbor_decode(b)), b), NA)
  # Deterministic input is a fixed point of decode -> encode (design 7.4).
  expect_identical(rt, determ, info = paste(cose$file[rt != determ], collapse = " | "))
  # What a signature or MAC covers is always deterministic, and so always
  # re-encodes to exactly the signed bytes.
  expect_true(all(determ[cose$kind != "output"]))
  # 127 messages have map keys out of bytewise order; nothing else.
  expect_identical(sum(!determ), 127L)
})

test_that("diagnostic notation agrees with cose-wg's, but for two defective examples", {
  cose <- utils::read.delim(test_path("fixtures", "cose-wg-examples.tsv"), quote = "",
                            colClasses = "character", na.strings = character())
  out <- cose[cose$kind == "output", ]
  norm <- function(s) gsub("\\s+", "", gsub("h'([0-9A-Fa-f]*)'", "h'\\L\\1'", s, perl = TRUE))
  same <- vapply(seq_len(nrow(out)), function(i)
    identical(norm(cbor_diagnose(hex_raw(out$hex[i]))), norm(out$diag[i])), NA)
  # fixtures/README.md: their notation shows a kid as bytes that the hex
  # encodes as text.
  expect_setequal(out$file[!same], c("x509-examples/signed-01.json", "x509-examples/signed-02.json"))
})

test_that("RFC 8392 CWT examples decode to the claims the RFC states", {
  spec <- utils::read.delim(test_path("fixtures", "spec-examples.tsv"), quote = "",
                            colClasses = "character")
  cwt <- spec[spec$source == "RFC 8392", ]
  expect_identical(nrow(cwt), 9L)
  for (h in cwt$hex) expect_true(cbor_validate(hex_raw(h)), info = h)

  claims <- cbor_decode(hex_raw(cwt$hex[cwt$label == "Example CWT Claims Set as Hex String"]))
  expect_identical(claims, cbor_map(
    list(1L, 2L, 3L, 4L, 5L, 6L, 7L),
    list("coap://as.example.com", "erikw", "coap://light.example.com",
         1444064944L, 1443944944L, 1443944944L, as.raw(c(0x0b, 0x71)))
  ))

  # A MACed CWT with the CWT tag: 61(17([protected, unprotected, payload, tag])).
  maced <- cbor_decode(hex_raw(cwt$hex[cwt$label == "MACed CWT with CWT Tag as Hex String"]))
  expect_identical(maced$tag, 61)
  expect_identical(maced$value$tag, 17)
  payload <- maced$value$value[[3]]
  expect_identical(cbor_decode(payload), claims)

  # A floating-point NumericDate survives, inside the MAC's payload. This
  # one is COSE_Mac0 alone, 17([...]), without the CWT tag.
  fp <- cbor_decode(hex_raw(cwt$hex[cwt$label == "MACed CWT with a Floating-Point Value as Hex String"]))
  expect_identical(fp$tag, 17)
  inner <- unclass(cbor_decode(fp$value[[3]]))
  expect_identical(inner$keys, list(6L))
  expect_identical(inner$values, list(1443944944 + 0.5))
})

test_that("the RFC 8428 SenML pack decodes to its records", {
  spec <- utils::read.delim(test_path("fixtures", "spec-examples.tsv"), quote = "",
                            colClasses = "character")
  pack <- cbor_decode(hex_raw(spec$hex[spec$source == "RFC 8428"]))
  expect_length(pack, 7L)
  first <- unclass(pack[[1]])
  get <- function(rec, key) rec$values[[which(vapply(rec$keys, identical, NA, key))]]
  expect_identical(get(first, -2L), "urn:dev:ow:10e2073a0108006:")   # bn
  expect_identical(get(first, -4L), "A")                             # bu
  expect_identical(get(first, -1L), 5L)                              # bver
  expect_identical(get(first, 0L), "voltage")                        # n
  expect_identical(get(first, 2L), f64("405e066666666666"))          # v = 120.1
  expect_identical(get(unclass(pack[[5]]), 2L), 1.5)                 # a half-precision value
})

test_that("WebAuthn Level 3 attestation objects decode, keys included, and round-trip", {
  spec <- utils::read.delim(test_path("fixtures", "spec-examples.tsv"), quote = "",
                            colClasses = "character")
  wa <- spec[spec$source == "WebAuthn L3", ]
  expect_identical(nrow(wa), 15L)
  # label -> attestation format, COSE key type, COSE algorithm (IANA).
  expected <- list(
    "ES256 Credential with No Attestation" = list("none", 2L, -7L),
    "ES256 Credential with Self Attestation" = list("packed", 2L, -7L),
    "Packed Attestation with ES384 Credential" = list("packed", 2L, -35L),
    "Packed Attestation with ES512 Credential" = list("packed", 2L, -36L),
    "Packed Attestation with RS256 Credential" = list("packed", 3L, -257L),
    "Packed Attestation with Ed25519 Credential" = list("packed", 1L, -8L),
    "Packed Attestation with Ed448 Credential" = list("packed", 1L, -53L),
    "TPM Attestation with ES256 Credential" = list("tpm", 2L, -7L),
    "Android Key Attestation with ES256 Credential" = list("android-key", 2L, -7L),
    "Apple Anonymous Attestation with ES256 Credential" = list("apple", 2L, -7L),
    "FIDO U2F Attestation with ES256 Credential" = list("fido-u2f", 2L, -7L)
  )
  for (i in seq_len(nrow(wa))) {
    x <- hex_raw(wa$hex[i])
    ao <- cbor_decode(x)
    expect_identical(cbor_encode(ao), x, info = wa$label[i])
    # authData: rpIdHash (32), flags (1), signCount (4), AAGUID (16),
    # credential ID length (2) and ID, then the COSE_Key.
    ad <- ao$authData
    n <- as.integer(ad[54]) * 256L + as.integer(ad[55])
    key <- unclass(cbor_decode_seq(ad[(56 + n):length(ad)])[[1]])
    get <- function(k) key$values[[which(vapply(key$keys, identical, NA, k))]]
    want <- expected[[wa$label[i]]]
    if (!is.null(want)) {
      expect_identical(ao$fmt, want[[1]], info = wa$label[i])
      expect_identical(get(1L), want[[2]], info = wa$label[i])
      expect_identical(get(3L), want[[3]], info = wa$label[i])
    }
  }
})
