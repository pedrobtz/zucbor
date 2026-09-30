# zucbor — Roadmap to 0.1.0 (first CRAN release)

Companion to [design.md](design.md). Section references (§) point there.

## Sequencing principles

1. **The check phase lands before the builder.** Limits, duplicate keys and validation are the security core (§4, §11). Building R objects first means retrofitting limits into code that already assumes they hold — that is how limit bugs ship.
2. **The encoder lands before hardening.** Round-trip is the strongest test oracle available (§16); every stage after it gets a better suite for free.
3. **Portability is proven at Stage 1, not discovered at Stage 8.** Vendoring is the largest schedule risk, and its traps (§13) surface on Windows and on old compilers.
4. **Every stage ends with something runnable and tested.** No stage is "write three files, test later".
5. **A stage is done when its exit criteria pass in CI on all three platforms**, not when the code is written.
6. **Gates need canaries.** A gate — lint, symbol check, fuzz, mutation — is trusted once it has been seen to fail on purpose, not before. `zuxml` shipped two gates that passed vacuously.
7. **Change the design in the same commit as the contract.** A stage that changes a decision in §18 edits design.md in that commit, along with the roxygen table and the tests that state it.

Sizes are relative: **S** ≈ a sitting, **M** ≈ a few, **L** ≈ the stage is the week.

**"v1" means the first release's scope**, here and in the design. It ships as 0.1.0 (Stage 9); 1.0.0 comes after a real consumer has used the API.

**Status never goes in a heading — issue links use the anchors.** A heading is `## Stage N — Title · Size` and nothing else; a stage's state is the **Status:** line directly under it. Status words in a heading change its GitHub anchor, which silently breaks every issue that links to the stage.

---

## Stage 0 — Repo hygiene and consumer inventory · S

**Status:** not started.

The package is the `usethis` skeleton; clear it before building on it.

**Do**
- `DESCRIPTION`: real `Title` and `Description`, `Authors@R` (Pedro Baltazar, `aut`/`cre`/`cph`), `URL` and `BugReports`, `Depends: R (>= 4.1)`, `Language: en-GB`. TinyCBOR's copyright holders are **not** added yet: declaring holders for code the package does not contain would be false (Stage 1).
- `LICENSE` / `LICENSE.md` name a real copyright holder.
- `.Rbuildignore`: `^tools$` (`^\.agents$` landed with these documents), and the `src/**/*.o`, `*.so`, `*.dll` patterns (`zujson` found stale objects shipped and relinked otherwise).
- `NEWS.md`: replace the usethis heading with `# zucbor 0.0.0.9000`, so check does not NOTE on news.
- Replace the template test with `tests/testthat/test-init.R`, asserting the DLL is loaded and registered.
- **Inventory the consumers.** Write down, in this file, which packages will call zucbor and how: from R, from C through a table, or linking an archive. `zuxml`'s 2026-09-22 review names skipping this as its most expensive mistake — it built a fixture for a consumer that never came and missed the one that existed. Today's candidates: `zuhttp` (`application/cbor`, R-level, `Suggests:`) and `zucrypt` (COSE, would need the deterministic encoder, possibly from C). If none is confirmed, §19 Q6 stays closed for v1.

**Exit**
- `R CMD check --as-cran` passes with only the development-version NOTE.
- The inventory is written, even if it says "none".

---

## Stage 1 — Vendor TinyCBOR and prove it builds · M

**Status:** not started.

The highest-risk stage. Do not proceed until it is green on Windows and on R-oldrel.

**Do**
- Import TinyCBOR 7.0 (§13) into `src/vendor/tinycbor/` — the listed files only — via `tools/update-tinycbor`; write `tools/tinycbor-files.txt`, `tools/verify-vendor`, `src/vendor/PROVENANCE`. Re-check upstream for a newer release first; checking rather than trusting the plan is the point of the step (`zuxml` found four releases and four CVEs between its design and its import).
- **Decide §19 Q7 (GCC < 11)** with whatever upstream has released by then, and record the decision in §13 and §18.
- Project-owned `src/tinycbor/tinycbor-export.h` and `tinycbor-version.h`, written by the update script.
- `src/Makevars` and `src/Makevars.win` with hand-listed `OBJECTS`; `-D__USE_MINGW_ANSI_STDIO=1` on Windows (trap 5).
- `tools/check-symbols`: `nm -u` over the built shared object, failing on `stdout`, `stderr`, `printf`, `puts`, `abort`, `exit` (trap 4). **Plant a `fprintf(stderr, …)` in a scratch copy and see it fail** before trusting it.
- **Licensing.** `Authors@R` gains Intel Corporation and S. Phirsov as `cph`, each with a comment naming TinyCBOR; `inst/COPYRIGHTS`; `LICENSE.note`; TinyCBOR's `LICENSE` stays in the vendor tree.
- `zucbor_info()`: TinyCBOR version, `CBOR_PARSER_MAX_RECURSIONS`, the default limits.
- One smoke `.Call` entry point that validates a fixed buffer through `cbor_value_validate()`, registered in `src/init.c`.

**Exit**
- Installs from source on Windows, macOS and Linux (release, devel, oldrel) with no CMake and no system library.
- R-devel compiles in C23 (trap 2); oldrel with its default standard.
- `tools/verify-vendor` reproduces the committed tree; `tools/check-symbols` passes and has been seen to fail.
- `R CMD check --as-cran` clean.

**Trap:** if a platform fights the build, fix configuration outside the vendor tree. A local patch to TinyCBOR is the last resort; if one is unavoidable, it lives in `tools/patches/`, is applied by `tools/update-tinycbor`, is named in `PROVENANCE`, and `verify-vendor` checks the patched result.

---

## Stage 2 — Check phase: walk, validation, limits, conditions · L

**Status:** not started.

The core. Everything after it relies on what this stage guarantees.

**Do**
- `src/zu_cond.c`: `zu_stop()` building classed conditions in C, the status-name table, the §10 hierarchy. `R/conditions.R` for R-side argument errors of the same shape. `?"zucbor-conditions"`.
- Argument validation for the three limits (§11): positive whole numbers, `Inf` where allowed, `max_depth` ≤ 1024.
- `src/zu_walk.c`: the iterative walk over a TinyCBOR iterator — explicit container stack in `R_alloc` scratch, depth including tags, `max_items` counting string chunks, byte offsets, trailing-byte check, `R_CheckUserInterrupt()` every 65,536 items.
- Duplicate keys by value (§6.5): per-map key descriptors, sorted, adjacent comparison. Every comparison class, including `1` against `0x1801`.
- `ZU_VALIDATE_FLAGS` and `cbor_value_validate()`; `deterministic = TRUE` adding `CborValidateCanonicalFormat` and the bignum-fits-an-integer rule.
- Sequence handling: item-by-item for the `*_seq` functions.
- **Export `cbor_validate()`**, the first user-facing function, since by §4 rule 2 it *is* this stage.
- `max_size` enforced before the walk; the 4-byte-length and 8-byte-length headers exercised.
- Tests, fixtures built inside each `test_that()`: RFC 8949 Appendix F not-well-formed examples; truncation at every byte of every Appendix A example; the §16 security list.

**Exit**
- Every Appendix F example is `zucbor_parse_error`; every Appendix A example validates.
- The 2^64-element header, 100,000 nested arrays and 100,000 nested tags each fail with their own class, no crash, no stack overflow — the deep cases also under a 1 MB stack (`ulimit -s`) in the sanitizer job.
- Each limit trips its own class with `limit` and `limit_value` set; a test enumerates every `CborError` in the vendored `cbor.h` and asserts it maps to a class or to a deliberate bare `zucbor_error`.
- ASan + UBSan (with `-UNDEBUG`, trap 3) clean over the suite.

---

## Stage 3 — Build phase: CBOR to R · L

**Status:** not started.

**Do**
- `src/zu_build.c`: recursion bounded by the checked depth, preallocation from checked counts, `zu_mkchar()` as the only CHARSXP maker with the NUL and length guards (§6.8).
- Integers and `big_integers` (§6.2); `src/zu_bigint.c` for decimal conversion; the 128-byte bignum cap (§6.6).
- The simplification lattice (§6.3), including the float-versus-integer-valued distinction for `cbor_bigint` and the classed-scalar rule for `POSIXct` / `Date`.
- Maps under all three `map_keys` modes (§6.4), and `duplicate_keys = TRUE` producing `cbor_map`.
- Tags under both `tags` modes; `src/zu_time.c` for RFC 3339 and civil dates.
- The four value classes: constructors that validate, `print`/`format`/`as.character`/`length`, `as.numeric.cbor_bigint`.
- Export `cbor_decode()`, `cbor_decode_seq()`; `cbor_read()` and `cbor_read_seq()` over the copied `R/zu_source.R` with the bounded `readBin()` loop (§9).
- **Write the §6 tables into roxygen now**, from this document, with one test per row.

**Exit**
- Every §6 row has a test; roxygen, design.md and tests agree.
- The COSE (RFC 9052), CWT (RFC 8392) and WebAuthn attestation fixtures decode to the values their specifications print.
- Clean under `gctorture(TRUE)`; the fifty-times interleaved failing/succeeding test (`zujson`'s memory-model check) passes.
- The interrupt test (`setTimeLimit()` inside the decode expression) unwinds, and the same input then decodes.
- `cbor_read()` on an endless connection stops one byte past `max_size`.

---

## Stage 4 — Deterministic encoder · L

**Status:** not started.

**Do**
- `src/zu_encode.c`: measure pass into a zero-length buffer, one `RAWSXP` of exact size, write pass (§8). Depth charged exactly as the decoder charges it.
- `src/zu_float.c`: width selection and half conversion, tested over all 65,536 half patterns.
- Map-key sorting over encoded keys in `R_alloc` scratch; duplicate and partial names refused (§7.2).
- The §7 mapping, including whole doubles as integers, `NaN` versus `NA`, `POSIXct` → tag 1, `Date` → tag 1004, `cbor_bigint` → integer or tag 2/3.
- Export `cbor_encode()`, `cbor_encode_seq()`; `self_describe`.
- **Round-trip property tests** (§16) over Appendix A, the fixtures, and generated nested values.

**Exit**
- Every Appendix A example in deterministic form encodes to its exact bytes.
- `cbor_validate(cbor_encode(x), deterministic = TRUE)` for every generated `x`.
- A checked-in hex fixture of a large mixed value is byte-identical on every CI platform — determinism across machines, not just across calls.
- `cbor_encode()` at `max_depth = d` never produces output `cbor_decode(max_depth = d)` refuses, at `d` and `d + 1`, including tags and nested maps.
- `gctorture(TRUE)` clean; `rchk` clean.

---

## Stage 5 — Diagnostic notation · S

**Status:** not started.

**Do**
- `src/zu_diag.c`: the `CborStreamFunction` callback over `cborpretty.c`, formatting with `vsnprintf()` into `R_alloc` scratch, the result copied into one CHARSXP.
- `cbor_diagnose()` runs the check phase first, so the pretty-printer never sees input the walk refused, and its output is bounded by a constant multiple of `max_size`.
- `print` methods for the value classes use diagnostic notation where it is clearer.

**Exit**
- Appendix A's diagnostic column matches for every example, or each difference is listed with the reason (TinyCBOR's spelling of floats and indefinite lengths differs in places).
- Windows output identical to Linux for 64-bit integers (trap 5).

---

## Stage 6 — Conformance and real-world corpus · M

**Status:** not started.

**Do**
- `tools/run-conformance` against `cbor/test-vectors` at a pinned commit: decode every vector; for each with `roundtrip: true`, encode and compare bytes. A baseline per category of known difference, attributed by rule, not by a list of file names, so a new deviation cannot hide in a known one (`zuxml`'s W3C harness).
- Fixture corpus in `tests/testthat/fixtures/`, small and licensed for redistribution: `cose-wg/Examples` messages, RFC 8392 CWTs, WebAuthn Level 3 test vectors, RFC 8428 SenML packs. Record each source and licence in the fixture directory.
- One test per fixture asserting the specification's stated values, not a snapshot of our own output.

**Exit**
- Conformance run at zero unexplained deviations, and seen to fail when a baseline is lowered or an entry removed.
- Every fixture decodes; every deterministic fixture round-trips byte-for-byte.

---

## Stage 7 — Hardening · L

**Status:** not started.

**Do**
- libFuzzer targets over the C layer: `fuzz_check`, `fuzz_roundtrip` (decode → encode → decode fixed point through an R-free harness), `fuzz_diag`. `fuzz/fuzz_canary.c` must crash through the same code path before any real target runs, and `tools/run-fuzz` exits non-zero if it does not. Capture the fuzzer's own exit status, not a pipe's (`zuxml` #35).
- Seeds from Appendix A, Appendix F and the Stage 6 fixtures; grown corpus cached between CI runs so fuzzing time accumulates.
- `native-checks.yaml` from `pedrobtz/r-actions`: ASan/UBSan with `-UNDEBUG`, valgrind, LTO, gctorture, `rchk` (blocking), the vendored-source guard, `tools/check-symbols`.
- `tools/run-mutation-check`: delete each guard — depth, items, size, duplicate keys, NUL, trailing bytes, the length-header trust rule — from a throwaway copy, and require its hostile input to stop being refused.
- `-Wall -Wextra -Wpedantic -Werror` over project-owned sources, seen to fail on a planted warning (`-fsyntax-only` alone exits 0 on warnings).
- A CI grep asserting no test opens a network connection.

**Exit**
- 24 h of fuzzing per target, cumulative across CI runs, with no finding in project-owned code.
- Every §16 security regression fails when its guard is removed.
- Zero warnings from project-owned sources.

---

## Stage 8 — Documentation, benchmarks, CRAN prep · M

**Status:** not started.

**Do**
- roxygen for every export, with runnable examples; the §6 and §7 tables and §7.4's lossy list in the help pages.
- Vignettes shipped in the tarball: *Decoding untrusted CBOR* (limits, duplicate keys, deterministic checking), *COSE and WebAuthn* (decoding an attestation object end to end, using only fixtures). A pkgdown-only getting-started article.
- README: what zucbor is, the one-screen mapping, and plainly what it is not (no signatures, no CDDL, no base64).
- `tools/run-benchmarks` against the §17 targets, with `zujson` as the comparison. Not in CI.
- `cran-comments.md`; `NEWS.md` bumped to `# zucbor 0.1.0` together with `Version:`; `inst/WORDLIST` regenerated.
- `R CMD check --as-cran --run-donttest` locally and on every CI row.

**Exit**
- Zero NOTEs beyond "New submission".
- Benchmarks meet §17, or each gap is documented with a measured reason.

---

## Stage 9 — First CRAN release · S

**Status:** not started.

- Verify each §20 acceptance criterion explicitly, in a table naming the test file, tool or CI job behind it. Writing it out is the check: `zuxml` found three criteria backed only by gates nothing else mentioned.
- Tag `v0.1.0`, submit, respond. A human step.
- 0.1.0, not 1.0.0: no consumer has used the API yet, and CRAN version numbers only go up.

---

## Risk register

| Risk | Stage | Mitigation |
|---|---|---|
| TinyCBOR fails to build on a platform or old compiler | 1 | Proven at Stage 1 on the full matrix; §13's eight traps named up front; GCC < 11 decided explicitly (§19 Q7) |
| `cbor_assert()` precondition violated in release builds is silent UB | 2–4 | Type checked before every accessor; sanitizers built with `-UNDEBUG` (§13, trap 3) |
| A length header drives an allocation | 2–3 | Check phase before build (§4, rule 1); permanent 2^64-header regression; mutation check |
| Duplicate keys let two parsers disagree on a signed structure | 2 | Rejected by value by default; every comparison class tested |
| Encoder output the decoder refuses | 4 | Depth charged identically; property test at `d` and `d + 1` |
| Non-determinism across platforms (float width, key order, locale) | 4 | Project-owned float code tested exhaustively; `memcmp` order; cross-platform hex fixture |
| The mapping grows until nobody can hold it in their head | all | §2's Never column; new classes only for values R cannot represent |
| Building a C API or streaming decoder for a caller that does not exist | all | Stage 0 inventory; §19 Q6; §9 rules streaming out |
| Upstream security release after pinning | after 1 | `tools/update-tinycbor` as a ten-minute job; watch upstream advisories |

---

## Explicitly not in v1

Data frames · UUID and URI conversion · CTAP2 length-first key order · streaming or incremental decode · a public C API · parsing diagnostic notation · base64 · signatures · CDDL.

Each is phase 2 in §2, an open question in §19, or permanently out of scope. None is made harder by shipping v1 first: `cbor_tag` already carries every unconverted tag, and a `key_order` argument would be additive.

---

## After v1

1. The first real consumer — likely `zuhttp`'s `application/cbor` support or `zucrypt`'s COSE — and whatever it shows the API gets wrong. 1.0.0 follows that.
2. Data frames, once SenML users ask (§19 Q3).
3. A C API, if and only if item 1 needs one (§19 Q6).
