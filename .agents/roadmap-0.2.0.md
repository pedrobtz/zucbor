# zucbor — Roadmap to 0.2.0

Companion to [design.md](design.md) and [roadmap.md](roadmap.md), which took the package to 0.1.0. Section references (§) point to the design. Stages are numbered on from the 0.1.0 roadmap, so an issue that says "Stage 12" means one thing.

**Status:** plan, 2026-10-01. Nothing here is implemented. Each stage's **Proposed decisions** become design decisions only when that stage lands, in the same commit as the code (the rule the 0.1.0 roadmap follows).

## Where this comes from

A survey of the most-used CBOR libraries elsewhere, read from their own documentation on 2026-10-01: Python's [cbor2](https://github.com/agronholm/cbor2), and in Node.js [cbor2](https://github.com/hildjj/cbor2) (the successor to `node-cbor`), [cbor-x](https://github.com/kriszyp/cbor-x) and [cborg](https://github.com/rvagg/cborg). Every feature they share that zucbor lacks was weighed against zucbor's three commitments: input is checked whole before anything is built (§4), encoding is deterministic (§8), and the mapping to R stays small enough to hold in your head.

| Feature | Seen in | Here |
|---|---|---|
| User-supplied tag decoders and type encoders | cbor2 (`tag_hook`, `default`); cbor2 (Node, `registerDecoder`, `toCBOR`); cborg (`tags`, `typeEncoders`) | Stage 10 |
| Decode the first item, return the remaining bytes | cborg (`decodeFirst`) | Stage 11 |
| Typed arrays, RFC 8746 tags 64–87, and multi-dimensional arrays (40, 1040) | cbor2 (Node), cbor-x | Stage 12 |
| Annotated hex dump | cbor2 (Node, `comment()`), and the cbor.me playground | Stage 13 |
| Tabular data | cbor-x (record structures); zujson's data frames in this family | Stage 14 |
| Reading a sequence item by item | cbor-x (streams), cbor2 (Node, `decodeStream`) | Stage 15 |
| Deterministic profiles: CDE and dCBOR | cbor2 (Node, `cde`, `dcbor`) | Deferred |
| Length-first ("RFC 7049 canonical") key order | cborg (default `mapSorter`), cbor2 (Node, `sortKeys`) | Deferred |
| Fine strictness switches (`rejectUndefined`, `allowNaN`, …) | cborg, cbor2 (Node) | Deferred |
| More built-in tags: UUID, IP address, decimal fraction, complex | cbor2 | Through Stage 10's handlers |
| Value sharing, string references, packed CBOR, record extension | cbor2, cbor-x | Not planned |
| Parsing diagnostic notation; CBOR to JSON | cborg (`diag2bin`, `bin2json`), cbor2 (tool) | Not planned |

## Sequencing principles

1. **Extensibility first.** Stage 10 decides how a tag that zucbor does not know gets meaning in R. Once it exists, UUIDs, IP addresses and decimals need recipes, not classes, and later stages can be built on it rather than beside it.
2. **New input goes through the check phase.** Every new validity rule (a typed array's length, a multi-dimensional array's shape) is a walk rule with a `/* GUARD */` marker and a case in `tools/run-mutation-check`, before the build phase relies on it.
3. **Defaults do not change bytes.** Every value 0.1.0 encodes must encode to the same bytes in 0.2.0: the cross-platform fixture in `test-encode.R` stays as it is. A new encoding is opt-in.
4. **The 0.1.0 API is kept.** Additions only: new arguments get defaults that reproduce 0.1.0 behaviour, and no function is renamed.
5. **The 0.1.0 gates apply unchanged:** green on every CI platform, rchk, gctorture, sanitizers with `-UNDEBUG`, the lint and mutation gates, the conformance runner, and design text changed in the same commit.

Sizes as before: **S** ≈ a sitting, **M** ≈ a few, **L** ≈ the stage is the week.

**Tracking.** The `v0.2.0` milestone holds umbrella issue #29, with one `stage` sub-issue per stage: Stage 10 is #30, and so on to Stage 16, which is #36. Each links to its heading here. Close a stage's issue when its exit criteria pass, and update its **Status:** line in the same PR. As in the 0.1.0 roadmap, status never goes in a heading.

**Context:** 0.1.0 has not been submitted when this work starts (`main` is `0.0.0.9000`), so these stages land on `main` before the first release. Principle 3 still binds: whatever is released first, existing values keep 0.1.0's bytes.

---

## Stage 10 — Tag handlers and an encoding generic · M

**Status:** done, 2026-10-01 (#30). Design §6.6, §7.5, §10, §12; decisions 28–30.

Lets a caller give meaning to a tag zucbor does not convert, and teach `cbor_encode()` a class it does not know, without the package growing a class for each.

**Proposed decisions**
- `cbor_decode(..., tag_handlers = NULL)`: a named list of functions, named by tag number (`list("37" = function(value) ...)`). A handler receives the tag's content as zucbor decoded it and returns any R value. It applies to the decoders and `cbor_read()` alike.
- A handler wins over zucbor's own conversion for that tag, so tag 0 can become a `Date` or a string if a caller wants. Tags with no handler follow `tags =` as now.
- Handlers run in the build phase, after the whole input has been checked: user code never sees bytes that are not well-formed and valid, and never runs before the limits have passed. A handler's result is an element of kind "other" (§6.3): it never joins an array's simplification.
- An error inside a handler becomes `zucbor_handler_error`, a `zucbor_error` subclass carrying `tag` and the original condition as `parent`. That is safe to raise from inside the build because everything it holds is `PROTECT`ed or `R_alloc()`ed (§12); the gctorture and sanitizer jobs must show it.
- Handlers are per call. There is no global registry, unlike Node's `Tag.registerDecoder()`: a call's result should not depend on what some other package registered.
- Encoding: an exported S3 generic, `as_cbor(x, ...)`. For an object whose class `cbor_encode()` does not know, the encoder calls it. A method returns something zucbor encodes, typically a `cbor_tag()`. The default method returns its input unchanged, which keeps 0.1.0's rule that an unknown class is encoded as its underlying type. A method that returns an object of the same class is refused, so it cannot recurse forever.
- UUIDs (37), IP addresses (52, 54) and decimal fractions (4, through the sibling `decimal` package when installed) become documented recipes in the examples article, not built-in conversions. That settles §19 Q2.

**Exit**
- Handlers for tags 0, 37 and 4 round-trip their values through `as_cbor()` methods.
- A handler that errors, one that returns a huge object, and one that calls `cbor_decode()` again are all tested. The last must see its own limits, not the outer call's.
- gctorture, rchk and the UBSan and ASan jobs are clean over the handler path. The interrupt test passes with a handler in the input.
- The cross-platform encoding fixture is unchanged.

**What actually happened**

- The proposed decisions held as written. Three details were settled on the way: an `as_cbor()` method's result is not converted again (only its elements are), so no chain of methods can loop and nothing needs counting; `AsIs` alone neither counts as known nor asks for a call, so `I(x)` of a class with a method is still converted; and an error in a method propagates unchanged, unlike one in a handler, because a method runs on the caller's data, not on input.
- **Map keys are now encoded in one pass.** Before, a non-text key was encoded twice, once to measure it, which would have run a key's `as_cbor()` method twice. It now goes into a buffer of its own owned like the output (§12).
- **A latent use after free was found by reading the encoder.** The per-depth map entry pools of Stage 8 could be allocated inside a parent map's `vmaxset()` mark, released with it, and reused by the next map at that depth under a different parent. No test or sanitizer had caught it, because the released block was not reused in between on the platforms tested. A map's end now forgets every deeper pool, and `tools/sanitizer-exercise.R`, which is what the ASan job runs, now has the shape that triggers it, as does `test-handlers.R`.
- **A design statement was wrong.** §6.6 said `tags = "keep"` reads a tag whose content has the wrong type; the check refuses it whatever `tags` says, and always has. Corrected rather than implemented: validity is the check's, and a handler gives meaning to valid content.
- Handler names are checked by their digits, not only as numbers: `"9007199254740993"` parses as 2^53 and would otherwise have matched that handler.
- The recipes went into the examples article: UUIDs (37) round-trip with a class and a method, IP addresses (52, 54) decode to text, and decimal fractions (4) round-trip through the `decimal` package, with the chunk skipped when it is not installed. A handler for tag 24 shows embedded CBOR decoded in place, with limits of its own.

---

## Stage 11 — Decoding a prefix · S

**Status:** done, 2026-10-01 (#31). Design §5; decision 31.

CBOR often sits inside binary framing. A WebAuthn `authData` puts a COSE key in the middle of fixed fields, and a CoAP payload follows a binary header. `cbor_decode()` refuses trailing bytes and `cbor_decode_seq()` needs every remaining byte to be CBOR, so neither reads "one item, then whatever comes next".

**Proposed decisions**
- `cbor_decode_prefix(x, ...)` takes the same arguments as `cbor_decode()` and returns `list(value = , consumed = )`. `consumed` is the number of bytes the item used, so `x[-seq_len(consumed)]` is the rest.
- The check phase covers the first item only. The bytes after it are not looked at and not trusted, and the documentation says so.
- An empty input is `zucbor_parse_error`, as for `cbor_decode()`.

**Exit**
- The COSE and WebAuthn vignette reads `authData`'s credential key with `cbor_decode_prefix()`, which also handles the extensions case without assuming that what follows is CBOR.
- Tests cover trailing garbage, trailing valid CBOR, an item exactly filling the input, and every Appendix A example with random bytes appended.
**What actually happened**

- The proposed decisions held as written. The check phase gained a `prefix` option that returns after the first item, before the trailing-bytes guard; the build phase was already item-at-a-time, so the decoder only reports where the item ended. The R side became `zu_decode(mode = 0, 1, 2)` rather than a second flag.
- TinyCBOR reads nothing past a top-level item (it preparses the next value only inside a container), so "not read" is literal, and a test appends a stray break, a truncated head, bad UTF-8, nesting past every limit, an absurd length and too many items after the item, all with no effect.
- The fuzz target gained two invariants: an input that passes as one item passes as a prefix consuming every byte, and a prefix consuming n bytes passes as one item over those n.
- The COSE and WebAuthn vignette now reads the credential key with `cbor_decode_prefix()` and checks the `ED` flag before treating anything after it as extensions.

---

## Stage 12 — Typed arrays (RFC 8746) · M

**Status:** done, 2026-10-01 (#32). Design §6.9, §7.6, §17; decision 32.

A numeric vector of a million elements is a million CBOR items today. RFC 8746 writes it as one tagged byte string, which is what R's numeric, integer and matrix data most need, and its tag 1040 is exactly R's column-major layout.

**Proposed decisions**
- **Decoding, always on.** Tags 64–75 and 77–87 become atomic vectors:
  - the signed 8-, 16- and 32-bit and unsigned 8- and 16-bit tags become `integer`;
  - unsigned 32-bit and the 64-bit tags become `double` when every element is within 2^53, and otherwise follow `big_integers`, as single integers do (§6.2);
  - the binary16, binary32 and binary64 tags become `double`, exactly;
  - tags 83 and 87 (binary128) stay `cbor_tag`, since no R type holds them.
- **Validity, in the check phase.** A typed array's content must be a byte string whose length is a multiple of the element size; otherwise `zucbor_invalid_error`, with an offset. This is a walk rule with a `GUARD` marker. The 0.1.0 tag-content table (§11) gains these tags.
- **Multi-dimensional arrays.** Tag 1040 (column-major) and tag 40 (row-major) are `[dimensions, elements]`. They decode to an R `matrix` or `array`, with tag 40's data transposed into R's order. The product of the dimensions must equal the number of elements, checked in the walk, and the dimensions are capped by `max_items` like any other count.
- **Encoding, opt-in:** `cbor_encode(..., typed_arrays = FALSE)`. With `TRUE`:
  - a `double` vector of length two or more becomes tag 86 (binary64, little-endian), keeping `NA_real_`'s payload, `NaN`, `-0` and every bit;
  - an `integer` vector becomes tag 78 (sint32, little-endian), with `NA_integer_` written as `INT_MIN`;
  - an R matrix or array becomes tag 1040, wrapping a typed array.

  Off by default, by principle 3, and because many decoders do not implement RFC 8746.
- Little-endian always, so the output is deterministic whatever the platform, and written byte by byte rather than with `memcpy()`, so a big-endian platform writes the same bytes.

**Exit**
- R → CBOR → R is identical for integer, double, matrix and array values, including `NA`, `NaN`, `-0` and infinities. CBOR → R → CBOR is a fixed point for typed arrays already in little-endian form.
- Big-endian and little-endian inputs decode to the same R value.
- The mutation check covers the length and shape guards, and `fuzz_check`'s seeds gain typed arrays.
- A benchmark records size and speed against plain arrays for 10^6 doubles.
**What actually happened**

- The proposed decisions held, with two refinements. A vector is written as a typed array whenever it would be written as an array, not only from length two: a decoded one-element typed array is marked `I()` and must re-encode as one. And a matrix of any type becomes tag 1040, with a plain elements array when it is not numeric, which RFC 8746 allows; the plan named only numeric ones.
- The check gained three guards, `typed-array-length`, `array-parts` and `array-shape`, each with a mutation case. The shape rule lives in the walk's frames: a frame records whether it is the content of tag 40 or 1040, its dimensions or its elements, and the product is checked when the content closes, saturating so that no product of huge dimensions can wrap round to the element count. The first `array-shape` guard spanned two lines, which the mutation tool's single-line edit cannot disable; it was rewritten rather than the tool loosened.
- A typed array counts as one item for `max_items`. `max_size` still bounds what R allocates, at four R bytes per input byte at worst (uint8 to `integer`), as for an array of small integers.
- A dimension above `INT_MAX` is a new `zucbor_unrepresentable` case (`ZU_ERR_DIMENSION`), raised in the build, since the CBOR is valid.
- A tag handler for the elements of a matrix is honoured: its result becomes the matrix if it is a vector of the right length, copied first since a handler may return a shared object, and otherwise the tag stays a `cbor_tag`.
- Benchmark (§17): for 10^6 doubles, 8.0 MB against 8.9 MB, encoding 2× and decoding 8× faster; for integers, 3.5× and 10×.

---

## Stage 13 — Annotated hex dump · S

**Status:** done, 2026-10-01 (#33). Design §5.

`cbor_diagnose()` shows what a message means; reviewing a signed message also needs where each byte went. Node's `cbor2` has `comment()`, and the cbor.me playground prints the same thing.

**Proposed decisions**
- `cbor_annotate(x, ...)`, with `cbor_diagnose()`'s arguments, returns a character vector of class `cbor_annotation`, one line per head or chunk: the offset, the bytes in hex, indentation by depth, and what they are (`map(2)`, `text(1) "a"`, `tag(1)`, `float16 1.5`).
- It runs only after the check, like `cbor_diagnose()`. Long strings show their first bytes and a count, so the output is bounded by a constant multiple of the input.
- The writer is project code beside the diagnostic printer in `src/zu_diag.c`, sharing its float and text formatting.

**Exit**
- Every Appendix A example annotates, with each byte of the input appearing exactly once in the hex column, checked mechanically.
- A COSE message from the conformance corpus reads correctly in the examples article.
**What actually happened**

- Long strings are not cut in the hex column, only in the preview: their content follows the head in rows of 16 bytes, so every byte appears exactly once for any input, not only for Appendix A, while the output stays bounded (indentation stops at 16 levels, previews at 32 bytes). The plan's "first bytes and a count" would have broken the exit criterion's own check on long strings.
- The writer reads heads by hand instead of through TinyCBOR's iterator, since the input is already checked; that keeps every chunk head and `break` byte on its own line, which the iterator's string API hides.
- Offsets are decimal and 0-based, as zucbor's conditions report them. C returns the three columns; R aligns them.
- The check runs over Appendix A and every one of the COSE corpus's unique items. The examples article annotates `sign1-tests/sign-pass-01.json`.

---

## Stage 14 — Data frames · M

**Status:** not started.

The one refusal in 0.1.0 that was scope rather than impossibility (§7.3, §19 Q3).

**Proposed decisions**
- **Encoding:** a data frame becomes an array of one text-keyed map per row, as in zujson (`zujson` §6). Each cell follows the ordinary mapping (§7.1), and `NA` becomes `null`. Row names are dropped and list columns are allowed. Within each row map, keys are sorted by the deterministic rule like any map's.
- **Decoding, opt-in:** `cbor_decode(..., data_frame = FALSE)`. With `TRUE`, an array whose elements are all text-keyed maps becomes a data frame:
  - its columns are the union of the keys, in first-seen order;
  - a missing key is `NA`;
  - each column simplifies by the array lattice (§6.3).
- **A cell budget,** `max_cells`, checked before allocation. zujson found that records sharing no keys make a frame quadratic in the input (72 kB of JSON asking for 5000 × 5000 cells), and that a body-size limit cannot stand in for it.

**Exit**
- Data frames round-trip modulo the documented losses (row names, factor levels, column order).
- The budget refuses a quadratic input before allocating.
- An RFC 8428 SenML example decodes to a frame in the examples article.

---

## Stage 15 — Reading a sequence item by item · M

**Status:** not started.

`cbor_read_seq()` reads the whole source, bounded by `max_size`. A long telemetry log should be readable in constant memory.

**Proposed decisions**
- `cbor_read_seq(file, ..., each = NULL)`. With a function, each item is decoded and passed to it as soon as its bytes are complete, nothing accumulates, and the call returns the number of items read.
- Each item is still checked whole before it is built, so §9's rule, no incremental decoding of a single item, still holds. `max_size` then bounds one item, not the stream.
- The walk must tell "the input ends inside this item" (read more) apart from "this item is malformed" (stop), which 0.1.0's check does not need to. That distinction is the stage's real work, and it is tested with every truncation of every Appendix A item.

**Exit**
- 10^6 items from a connection are read in memory bounded by the largest item.
- An interrupt during the read unwinds cleanly.
- A malformed item stops the read with its offset in the stream.

---

## Stage 16 — Release 0.2.0 · S

**Status:** not started.

`NEWS.md` lists every addition. The acceptance table is extended for Stages 10–15, the cross-platform encoding fixture still matches 0.1.0's bytes, and `R CMD check --as-cran` is clean on every platform. Tag and submit: a human step, as for 0.1.0.

---

## Deferred, with the reason

| Item | Why not now | What would bring it in |
|---|---|---|
| CDE profile (`deterministic = "cde"`) | The IETF draft *CBOR Common Deterministic Encoding* expired on 2026-04-17 at revision 13, without becoming an RFC | Publication as an RFC or BCP |
| dCBOR profile | An individual draft (revision 18), not a working-group document. zucbor already writes whole doubles as integers, which is dCBOR's numeric reduction | A caller using dCBOR, such as Blockchain Commons tooling |
| Length-first key order (CTAP2's "canonical") | Decoding CTAP2 data needs nothing: signatures cover bytes, not re-encodings (§19 Q1) | Someone emulating an authenticator |
| Strictness switches (`reject_undefined`, `allow_nan`, …) | Stage 10's handlers and `deterministic = TRUE` cover the cases seen so far | A protocol that must refuse one specific construct |
| Built-in UUID, IP address, decimal and complex conversion | Stage 10 makes each a recipe of a few lines | Enough repeated recipes to justify a class |

## Not planned

- **Value sharing and string references** (tags 28, 29, 25, 256), packed CBOR, and cbor-x's record extension. These compression schemes are rarely interoperable, and references let a small input expand without bound, the amplification the limits exist to stop.
- **Parsing diagnostic notation** (cborg's `diag2bin`). A second input parser is more attack surface, and it buys only convenience (§2).
- **CBOR to JSON.** `zujson::json_write(cbor_decode(x))` already does it, in two calls.

## Risk register

| Risk | Stage | Mitigation |
|---|---|---|
| A handler's error or interrupt leaks C state | 10 | Build-phase state is all R-owned (§12). gctorture, sanitizers and the interrupt test run over the handler path |
| `as_cbor()` methods make encoding non-deterministic | 10 | The method's output goes through the same deterministic encoder. The fixture test stays unchanged |
| Typed arrays change existing encodings | 12 | Opt-in. The cross-platform fixture is unchanged by construction |
| Endianness bugs on a platform CI does not cover | 12 | Byte-by-byte reads and writes, never `memcpy()`. Both endiannesses are tested on input |
| Data-frame decoding blows up quadratically | 14 | `max_cells`, checked before allocation, as zujson learned |
| Telling truncation from malformation goes wrong | 15 | Every truncation of every Appendix A item, and QCBOR's vectors, fed in chunks |
