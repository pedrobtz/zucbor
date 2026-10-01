# Tag handlers (cbor_decode(tag_handlers =)) and as_cbor(): Stage 10, design
# sections 6.6 and 7.5.

test_that("a handler gets the tag's content, decoded, and its result replaces the tag", {
  x <- cbor_encode(list(a = cbor_tag(37, as.raw(1:16)), b = cbor_tag(40000, list(1L, "x"))))
  seen <- list()
  v <- cbor_decode(x, tag_handlers = list(
    "37" = function(value) { seen[["37"]] <<- value; "uuid" },
    "40000" = function(value) { seen[["40000"]] <<- value; length(value) }
  ))
  expect_identical(v, list(a = "uuid", b = 2L))
  expect_identical(seen[["37"]], as.raw(1:16))
  expect_identical(seen[["40000"]], list(1L, "x"))
  # The content is decoded with the call's own options.
  v <- cbor_decode(cbor_encode(cbor_tag(9, c(1L, 2L))), simplify = "none",
                   tag_handlers = list("9" = identity))
  expect_identical(v, list(1L, 2L))
})

test_that("a handler wins over zucbor's conversion and over tags = \"keep\"", {
  stamp <- hex_raw("c074323031332d30332d32315432303a30343a30305a")
  expect_identical(cbor_decode(stamp, tag_handlers = list("0" = identity)), "2013-03-21T20:04:00Z")
  expect_identical(cbor_decode(stamp, tags = "keep", tag_handlers = list("0" = nchar)), 20L)
  expect_identical(cbor_decode(hex_raw("c249010000000000000000"), tag_handlers = list("2" = length)), 9L)
  expect_identical(cbor_decode(hex_raw("d9d9f701"), tag_handlers = list("55799" = function(v) v + 1L)), 2L)
  # Tags without a handler follow `tags`.
  v <- cbor_decode(hex_raw("82c11a514b67b0d82501"), tags = "keep", tag_handlers = list("37" = identity))
  expect_s3_class(v[[1]], "cbor_tag")
  expect_identical(v[[2]], 1L)
})

test_that("a handler's result does not join an array's simplification", {
  x <- cbor_encode(list(1L, cbor_tag(99, 2L), 3L))
  expect_identical(cbor_decode(x, tag_handlers = list("99" = identity)), list(1L, 2L, 3L))
  # A handler on a map key makes the map a cbor_map, as any non-text key does.
  m <- cbor_decode(cbor_encode(cbor_map(list(cbor_tag(99, "k")), list(1L))),
                   tag_handlers = list("99" = identity))
  expect_s3_class(m, "cbor_map")
  expect_identical(unclass(m)$keys, list("k"))
})

test_that("handlers run for each item of a sequence, and through cbor_read()", {
  x <- cbor_encode_seq(list(cbor_tag(99, 1L), 2L, cbor_tag(99, 3L)))
  h <- list("99" = function(v) v * 10L)
  expect_identical(cbor_decode_seq(x, tag_handlers = h), list(10L, 2L, 30L))
  path <- withr::local_tempfile(fileext = ".cbor")
  writeBin(x, path)
  expect_identical(cbor_read_seq(path, tag_handlers = h), list(10L, 2L, 30L))
  writeBin(cbor_encode(cbor_tag(99, 4L)), path)
  expect_identical(cbor_read(path, tag_handlers = h), 40L)
})

test_that("a handler never runs on input that fails the check", {
  calls <- 0L
  h <- list("99" = function(v) { calls <<- calls + 1L; v })
  tagged <- cbor_encode(cbor_tag(99, 1L))
  inputs <- list(
    c(tagged, as.raw(0x00)),                                    # trailing byte
    cbor_encode(list(cbor_tag(99, 1L), 1:300)),                 # over max_items
    c(hex_raw("82d86301"), as.raw(c(0x61, 0xff))),              # text not UTF-8
    hex_raw("82d863016162ff")                                   # break outside indefinite item
  )
  got <- fault_class(inputs, function(x) cbor_decode(x, max_items = 100, tag_handlers = h))
  expect_identical(unname(got), c("zucbor_parse_error", "zucbor_item_limit",
                                  "zucbor_invalid_error", "zucbor_parse_error"))
  expect_identical(calls, 0L)
})

test_that("an error in a handler is zucbor_handler_error with the tag and the parent", {
  x <- cbor_encode(list(1L, cbor_tag(37, as.raw(1:16))))
  e <- tryCatch(cbor_decode(x, tag_handlers = list("37" = function(v) stop("boom"))),
                error = identity)
  expect_s3_class(e, "zucbor_handler_error")
  expect_s3_class(e, "zucbor_error")
  expect_identical(e$tag, 37)
  expect_s3_class(e$parent, "simpleError")
  expect_identical(conditionMessage(e$parent), "boom")
  expect_identical(e$call[[1]], quote(cbor_decode))
  # A warning is not an error: it passes through, and the result stands.
  expect_warning(v <- cbor_decode(x, tag_handlers = list("37" = function(v) { warning("hm"); 0L })), "hm")
  expect_identical(v, list(1L, 0L))
})

test_that("a handler can decode embedded CBOR, with limits of its own", {
  inner <- cbor_encode(list(list(list(list(1L)))))      # four levels deep
  x <- cbor_encode(list(cbor_tag(24, inner)))
  h <- function(depth) list("24" = function(v) cbor_decode(v, max_depth = depth))
  # The outer call's max_depth (3) does not reach into the embedded item ...
  expect_identical(cbor_decode(x, max_depth = 3, tag_handlers = h(8)), list(cbor_decode(inner)))
  # ... and the embedded call's own limit is its own.
  e <- tryCatch(cbor_decode(x, tag_handlers = h(2)), error = identity)
  expect_s3_class(e, "zucbor_handler_error")
  expect_s3_class(e$parent, "zucbor_depth_limit")
  # Handlers nest: the embedded call can have handlers of its own.
  inner <- cbor_encode(cbor_tag(99, 5L))
  v <- cbor_decode(cbor_encode(cbor_tag(24, inner)), tag_handlers = list(
    "24" = function(v) cbor_decode(v, tag_handlers = list("99" = function(w) w + 1L))
  ))
  expect_identical(v, 6L)
})

test_that("a handler may return a large value, and many handlers may run", {
  x <- cbor_encode(lapply(1:2000, function(i) cbor_tag(99, i)))
  v <- cbor_decode(x, tag_handlers = list("99" = function(v) numeric(v)))
  expect_length(v, 2000L)
  expect_length(v[[2000]], 2000L)
  big <- cbor_decode(cbor_encode(cbor_tag(99, 1L)), tag_handlers = list("99" = function(v) numeric(1e6)))
  expect_length(big, 1e6)
})

test_that("tag_handlers must be a list of functions named by tag number", {
  x <- cbor_encode(1L)
  f <- identity
  bad <- list(
    f, list(f), list("1" = 1), list("01" = f), list("-1" = f),
    list("1e3" = f), list("1.0" = f), list(" 1" = f), list("9007199254740993" = f),
    structure(list("1" = f), class = "foo"), setNames(list(f, f), c("1", "1")),
    setNames(list(f), NA_character_)
  )
  got <- vapply(bad, function(h) tryCatch({cbor_decode(x, tag_handlers = h); "ok"},
                                          error = function(e) class(e)[1]), "")
  expect_identical(got, rep("zucbor_invalid_argument", length(bad)))
  e <- tryCatch(cbor_decode(x, tag_handlers = 1), error = identity)
  expect_identical(e$arg, "tag_handlers")
  expect_identical(cbor_decode(x, tag_handlers = list()), 1L)
  expect_identical(cbor_decode(x, tag_handlers = list("9007199254740992" = f)), 1L)
})

test_that("a tag beyond 2^53 never matches a handler", {
  # Tag 2^53 + 1 rounds to 2^53 as a double; it must not reach that handler.
  x <- hex_raw("db0020000000000001" |> paste0("01"))
  expect_error(cbor_decode(x, tag_handlers = list("9007199254740992" = function(v) "wrong")),
               class = "zucbor_unrepresentable")
})

# ---- as_cbor() -------------------------------------------------------------

test_that("as_cbor()'s default returns its input, and an unknown class is its underlying type", {
  foo <- structure(1:3, class = "zt_unknown")
  expect_identical(as_cbor(foo), foo)
  expect_cbor(foo, "83010203")
  expect_cbor(structure(list(a = 1L), class = "zt_unknown"), "a1616101")
})

test_that("an as_cbor() method decides how a class is written", {
  local_as_cbor("zt_point", function(x, ...) cbor_tag(99, unclass(x)))
  p <- structure(c(1L, 2L), class = "zt_point")
  expect_cbor(p, "d86382 0102" |> gsub(pattern = " ", replacement = ""))
  expect_cbor(list(p, I(p)), "82d8638201 02d863820102" |> gsub(pattern = " ", replacement = ""))
  expect_cbor(list(k = p), "a1616bd863820102")
  # A cbor_map key is converted too, once.
  calls <- 0L
  local_as_cbor("zt_key", function(x, ...) { calls <<- calls + 1L; unclass(x) })
  expect_cbor(cbor_map(list(structure("k", class = "zt_key")), list(1L)), "a1616b01")
  expect_identical(calls, 1L)
})

test_that("as_cbor() is not called for classes cbor_encode() knows", {
  boom <- function(x, ...) stop("as_cbor() should not be called")
  for (cls in c("Date", "POSIXct", "factor", "cbor_tag", "AsIs")) local_as_cbor(cls, boom)
  expect_cbor(as.Date("2024-02-29"), "d903ec6a323032342d30322d3239")
  expect_cbor(utc(0), "c100")
  expect_cbor(factor("a"), "6161")
  expect_cbor(cbor_tag(99, 1L), "d86301")
  expect_cbor(I(1L), "8101")
})

test_that("a method's result is written as it is: converted once, elements again", {
  local_as_cbor("zt_a", function(x, ...) structure(list(structure(5L, class = "zt_b")), class = "zt_c"))
  local_as_cbor("zt_b", function(x, ...) cbor_tag(98, unclass(x)))
  local_as_cbor("zt_c", function(x, ...) stop("the result is not converted again"))
  expect_cbor(structure(1L, class = "zt_a"), "81d86205")
  # Same class back is refused: most likely a method that forgot to convert.
  local_as_cbor("zt_same", function(x, ...) structure(unclass(x) + 1L, class = "zt_same"))
  expect_error(cbor_encode(structure(1L, class = "zt_same")), class = "zucbor_unsupported_type")
  # A method that returns its input is the default: the underlying type.
  local_as_cbor("zt_self", function(x, ...) x)
  expect_cbor(structure(7L, class = "zt_self"), "07")
})

test_that("an error in a method propagates unchanged, and nothing leaks", {
  local_as_cbor("zt_err", function(x, ...) stop(structure(class = c("zt_cond", "error", "condition"),
                                                          list(message = "no", call = NULL))))
  expect_error(cbor_encode(list(a = 1:300, b = structure(1L, class = "zt_err"))), class = "zt_cond")
  expect_cbor(list(1L), "8101")
})

test_that("a method can encode embedded CBOR, and counts toward max_depth", {
  local_as_cbor("zt_embed", function(x, ...) cbor_tag(24, cbor_encode(unclass(x), max_depth = 8)))
  v <- structure(list(list(list(1L))), class = "zt_embed")
  bytes <- cbor_encode(list(v), max_depth = 3)
  expect_identical(cbor_decode(bytes, tag_handlers = list("24" = cbor_decode)),
                   list(cbor_decode(cbor_encode(unclass(v)))))
  expect_error(cbor_encode(list(list(v)), max_depth = 2), class = "zucbor_depth_limit")
})

test_that("handlers and methods round-trip tags 0, 37 and 4", {
  # Tag 0 kept as its text, in a class of its own.
  local_as_cbor("zt_stamp", function(x, ...) cbor_tag(0, unclass(x)))
  stamp <- hex_raw("c074323031332d30332d32315432303a30343a30305a")
  v <- cbor_decode(stamp, tag_handlers = list("0" = function(s) structure(s, class = "zt_stamp")))
  expect_identical(cbor_encode(v), stamp)

  # Tag 37, RFC 9562 UUID: 16 bytes.
  local_as_cbor("zt_uuid", function(x, ...) cbor_tag(37, unclass(x)))
  uuid <- hex_raw("d82550f81d4fae7dec11d0a76500a0c91e6bf6")
  v <- cbor_decode(uuid, tag_handlers = list("37" = function(b) structure(b, class = "zt_uuid")))
  expect_s3_class(v, "zt_uuid")
  expect_identical(cbor_encode(v), uuid)

  # Tag 4, decimal fraction: 273.15 is [-2, 27315] (RFC 8949 section 3.4.4).
  local_as_cbor("zt_decimal", function(x, ...) cbor_tag(4, list(x$exponent, x$mantissa)))
  dec <- hex_raw("c48221196ab3")
  v <- cbor_decode(dec, tag_handlers = list("4" = function(em)
    structure(list(exponent = em[[1]], mantissa = em[[2]]), class = "zt_decimal")))
  expect_identical(c(v$exponent, v$mantissa), c(-2L, 27315L))
  expect_identical(cbor_encode(v), dec)
})

test_that("nested maps at the same depth under different parents encode correctly", {
  # Each map's sort buffer at a given depth is reused; a buffer for a deeper
  # level is released with its parent's scratch and must not be reused
  # afterwards. tools/sanitizer-exercise.R repeats this for the ASan job.
  inner <- function(i) setNames(as.list(1:40), paste0("k", 40:1, "_", i))
  mid <- function(i) list(m1 = inner(i), m2 = inner(i + 1))
  x <- list(p = mid(1), q = mid(3), r = mid(5))
  bytes <- cbor_encode(x)
  expect_identical(cbor_encode(cbor_decode(bytes)), bytes)
  v <- cbor_decode(bytes)
  expect_identical(v$q$m2[["k7_4"]], 34L)
})
