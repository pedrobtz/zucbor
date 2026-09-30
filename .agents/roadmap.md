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

**Tracking.** The `v0.1.0` milestone holds umbrella issue #4, and each stage has one `stage`-labelled sub-issue: Stage 0 is #5, and so on to Stage 9, which is #14. Each issue links to its stage's heading here, and this file stays authoritative. Close a stage's issue when its exit criteria pass, and update its **Status:** line in the same PR.

---

## Stage 0 — Repo hygiene and consumer inventory · S

**Status:** complete.

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

**Consumer inventory (2026-09-30)**

| Candidate | How it would consume zucbor | Confirmed? |
|---|---|---|
| `zuhttp` | R-level, `Suggests:`, for an `application/cbor` body helper | No. Its design mentions neither CBOR nor COSE |
| `zucrypt` | R-level, or C through a table, to build COSE `Sig_structure` bytes deterministically | No. Its design mentions neither CBOR nor COSE |
| any other sibling | — | None of the checked-out `zu*` repositories mention CBOR or COSE |

**No consumer is confirmed.** So the v1 scope is the R API alone: §19 Q6 (a C API) stays closed, there is no C fixture package to build at Stage 4 or 7, and nothing in the R API is shaped around a particular sibling. The first real consumer is the gate for 1.0.0 (*After v1*).

**What actually happened**

- `R CMD check --as-cran` came back 0/0/0 locally. The development-version NOTE did not appear, because it comes from the CRAN-incoming checks, which `devtools::check()` runs only when asked to.
- `devtools::document()` with roxygen2 8.1.0 replaced `RoxygenNote: 8.0.0` with `Config/roxygen2/version: 8.1.0`, as it did in zuxml. Keep roxygen2 at 8.1.0 or newer, or `document()` will rewrite `man/`.
- `git rm` of the template test left `tests/testthat/` empty, so git dropped the directory until `test-init.R` was written. An empty `tests/testthat/` next to `tests/testthat.R` is a hard check error (zuxml Stage 0), so the init test cannot come later.

---

## Stage 1 — Vendor TinyCBOR and prove it builds · M

**Status:** complete.

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

**What actually happened**

- **7.0 is still upstream's newest release** (re-checked 2026-09-30), so the pin stands and §19 Q7 closed as decision 23: ship 7.0, state GCC ≥ 11 in the README at Stage 8. The import's tarball SHA-256 and tag commit match the ones recorded when the design was written.
- **Only one copyright holder.** The design named S. Phirsov as a second `cph`, but that notice is only in upstream files outside the vendored subset. `Authors@R` lists Intel Corporation alone, and design §14 now says why. Declaring a holder whose code the package does not contain would have been as false as declaring one too early.
- **The subset links on its own.** Every `cbor_*` symbol resolves inside the five compiled files, and nothing calls `malloc`, stdio or `abort`. With `_Float16` available, clang emits calls to the compiler runtime's half-float helpers (`__extendhfsf2`, `__truncsfhf2`), which is trap 6 turning up in practice. The full CI matrix is what shows each platform's runtime provides them.
- **`tools/check-symbols` needed `assert` in its list.** R CMD check reports `__assert_fail` / `__assert_rtn` as it reports `abort`. The check fails on a `load_all()` build, whose `-UNDEBUG` keeps TinyCBOR's `assert()`s, and passes on an `R CMD INSTALL` build under R's `-DNDEBUG`. That split was the first canary. The second was a planted `fprintf(stderr, …)`, caught through `__stderrp`: clang had rewritten the `fprintf` into an `fwrite`, so the symbol that exposed it was the stream, not the function. A symbol check that listed only function names would have passed it.
- **`tools/verify-vendor` was seen to fail** on a one-byte edit, a stray file, and a version header that disagreed with `PROVENANCE`, each reported separately.
- **One `Makevars`, no `Makevars.win`.** R on Windows falls back to `Makevars`, so the object list exists once. `__USE_MINGW_ANSI_STDIO` is set there and is inert off Windows.
- **The depth ceiling is 1023, not 1024.** The design took `CBOR_PARSER_MAX_RECURSIONS` (1024) as the ceiling. Reading `cborvalidation.c` while planning Stage 2 showed the validator charges a level before testing it, and a probe confirmed it: 1023 nested arrays, or 1023 nested tags, validate, and 1024 fail with `CborErrorNestingTooDeep`. `ZU_MAX_DEPTH_CAP` is 1023, `zucbor_info()` reports it, and design §11 says why. The macro lives in TinyCBOR's internal header, so `src/zu_tinycbor_check.c` includes the internals, with no R headers, and `#error`s unless the cap is `CBOR_PARSER_MAX_RECURSIONS - 1`. Caught before merging, so no released number ever said 1024.
- **R's headers need C11.** Project files compile clean under `-Wall -Wextra -Wpedantic -Werror` as gnu17 and gnu2x. As gnu99 the build fails inside R's `R_ext/Complex.h` (an anonymous struct), not in zucbor.
- The `vendor` workflow runs `tools/verify-vendor` and the r-actions PR guard, plus a `symbols` job running `tools/check-symbols` on an `R CMD INSTALL` build.

---

## Stage 2 — Check phase: walk, validation, limits, conditions · L

**Status:** complete.

The core. Everything after it relies on what this stage guarantees.

**Do**
- `src/zu_cond.c`: `zu_stop()` building classed conditions in C, the status-name table, the §10 hierarchy. `R/conditions.R` for R-side argument errors of the same shape. `?"zucbor-conditions"`.
- Argument validation for the three limits (§11): positive whole numbers, `Inf` where allowed, `max_depth` ≤ 1023.
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

**What actually happened**

- **TinyCBOR's tag-content table is wrong for tag 1.** `CborValidateTagUse` allows only an integer under tag 1, so Appendix A's `1(1363896240.5)`, an epoch time as a float that RFC 8949 §3.4.2 explicitly allows, failed validation. The same table also refuses most content under tags 21–23, which may wrap any item. Tag content is now checked by the walk, against the table in design §11: TinyCBOR's, corrected, plus 100 and 1004. That turned out better than the plan in one respect: these faults now carry the tag's offset, which the validator could never give. The Appendix A test found this, and upstream has not been told yet.
- **UBSan found a bug on its first run.** `check_duplicates()` formed `w->keys + base` before testing whether there were two keys to compare, and for a map with no keys `w->keys` is still NULL. `NULL + 0` is undefined in C. It was harmless on every real compiler, and exactly what the sanitizer job exists for. It was found by a local UBSan build with TinyCBOR's assertions live (`-UNDEBUG`), before CI ran.
- **The depth ceiling, measured.** The ceiling Stage 1 corrected to 1023 holds from R: `max_depth = 1023` accepts 1023 nested arrays or tags, the next level is `zucbor_depth_limit`, and `max_depth = 1024` is `zucbor_invalid_argument`. 100,000 nested arrays, tags or indefinite arrays stop at the default limit.
- **Length headers are guarded twice.** TinyCBOR refuses container lengths of 2^32 and over as `CborErrorDataTooLarge`, which reads like a limit rather than a truncation. The walk checks every definite length against the bytes left first (each element costs at least one), so a nine-byte `9b ff…ff` is a `zucbor_parse_error` at offset 0 and never reaches TinyCBOR's size arithmetic.
- **TinyCBOR 7.0's chunk API differs from its own documentation.** The doc comment says the chunk getter returns a NULL pointer at the end. In 7.0 it returns `CborErrorNoMoreStringChunks`, and iteration must be bracketed by `cbor_value_begin_string_iteration()` / `…_finish_…()`. Following the doc would have walked off a definite string into the next item.
- **`cbor_validate(error = TRUE)`** was added. The tests needed the classed condition without building a value, and so will users; design §5 records it.
- **Appendix A test vectors carry one RFC 7049 leftover.** `cbor/test-vectors` still lists `f818` (`simple(24)`) as valid, which RFC 8949 erratum 5917 made not well-formed. The embedded vectors drop it from Appendix A and test it as a must-reject case.
- **Duplicate detection sorts.** It is a merge sort per map, not `qsort()`, whose worst case on an attacker-chosen key order is not guaranteed. A 20,000-key map validates in well under a second.
- **`shuffle = TRUE` reorders a file's top-level definitions, not only its tests.** Small helpers defined at the top of three test files were intermittently undefined, and only the shuffled runs showed it. Shared helpers now live in `tests/testthat/helper-expect.R`.
- `tools/check-status-table` keeps `zu_cond.c`'s `CborError` table equal to the vendored `cbor.h`. It was seen to fail with one name removed, and it runs in the `vendor` workflow. `native-checks.yaml` arrives here rather than at Stage 7: UBSan over the suite, the ASan containers over `tools/sanitizer-exercise.R`, valgrind, LTO, gctorture and a blocking `rchk`.

---

## Stage 3 — Build phase: CBOR to R · L

**Status:** complete.

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

**What actually happened**

- **Every Appendix A example decodes to the value it states,** checked with `identical()`. That covers `-0.0` keeping its sign, `1(1363896240.5)` as a fractional `POSIXct`, `{1: 2, 3: 4}` as a `cbor_map`, and all four 64-bit boundary integers and bignums as exact `cbor_bigint`.
- **Bignums decode by value, which the design did not say.** §6.6 had tags 2 and 3 always becoming `cbor_bigint`. But duplicate keys are already compared by value, and `2(h'01')` *is* the integer 1. So a bignum now goes through the same integer ladder as a plain integer: `1L`, a double up to 2^53, and past that whatever `big_integers` says. Design §6.2 and §6.6 were amended in this commit.
- **TinyCBOR's diagnostic printer suffixes floats (`1.5f16`).** It has no flag to omit the suffix, only a choice between `f16` and `_1`. That is fine for `cbor_diagnose()`, but it made `map_keys = "string"` name a half-float key `1.5f16`. Float keys are now named by the shortest round-trip decimal, formatted by zucbor. Every other non-text key keeps TinyCBOR's notation.
- **A NUL inside a tag 0 string is not unrepresentable, it is simply not a date.** The design's security list had it as `zucbor_unrepresentable`, but that text never becomes an R string. It is `zucbor_invalid_error`, and §16 says so now.
- **`gctorture(TRUE)` over every Appendix A example plus the lattice and map-key cases,** under two option sets and an error path, gives results `identical()` to the untortured run. The local UBSan build with `-UNDEBUG` is clean over the suite and the extended `tools/sanitizer-exercise.R`, which now drives decoding under every mapping option.
- **The interrupt criterion is tested, not argued.** `setTimeLimit(elapsed = 0.01)` inside the same expression as decoding 4 million empty arrays fires from the `R_CheckUserInterrupt()` call sites, and the same input then decodes in full. zuxml waited two stages for want of this technique (its #37).
- **`R_FindNamespace` plus a quoted call** raises build-phase faults from C with the user's call attached. The call is wrapped in `quote()` before the evaluated expression is built. An unquoted language object as an argument would have run the user's `cbor_decode(...)` call a second time inside the error handler.
- **CI found two things the local runs could not.**
  - *macOS arm64:* R's parser does not round every decimal literal correctly where `long double` is only a double, so the test literal `5.960464477539063e-08` came out one ulp away from 2^-24, which the decoder had produced exactly. Tests now build exact floats from their bits (`f64()`, `f32()`) or from exact arithmetic. The C code stopped using `R_strtod()`, which has the same weakness, in favour of the C library's correctly rounded `strtod()`. R keeps `LC_NUMERIC` at `"C"`, so the decimal point is safe.
  - *rchk:* `Rf_setAttrib(out, Rf_install("tzone"), Rf_mkString("UTC"))` passed two unprotected arguments. The string is PROTECTed first now.
- **R's `close()` destroys a connection.** A test that asked `isOpen()` of a connection `cbor_read()` had opened and closed got "invalid connection". That is what closing means in R, so the test now expects exactly that.

---

## Stage 4 — Deterministic encoder · L

**Status:** complete.

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

**What actually happened**

- **The encoder is project code, not TinyCBOR's.** Deterministic encoding needs each map's keys encoded, sorted and spliced into the output. TinyCBOR's encoder has no call that appends pre-encoded bytes, and `cbor_encoder_close_container()` checks item counts, so splicing would fail with `TooFewItems`. `src/zu_encode.c` is one routine run twice: measure, then write into one exactly sized `RAWSXP`. `cborencoder.c` left the vendored subset through `tools/update-tinycbor`, and the vendor guard now requires only `PROVENANCE`, since `test-info.R`'s literal already fails on a version bump.
- **The round-trip property test changed the decoder twice.** Generated values that must satisfy `cbor_encode(cbor_decode(b)) == b` found two things the design had wrong:
  - *One-element arrays.* `[x]` decoded to a length-one vector, which `auto_unbox` then wrote as a bare `x`. Every one-element array lost its brackets, which would corrupt a WebAuthn `x5c` holding one certificate. One-element arrays now decode as `I()` values, the marker the encoder already honours.
  - *Booleans.* The lattice borrowed from `zujson` let logical join the numbers, so `[false, 1.5]` became `c(0, 1.5)` and re-encoded as `[0, 1.5]`. Logical is now a kind of its own.

  Both are design §6.3 decisions 25 and 26. Neither would have been found by testing the encoder against fixed examples.
- **R's byte-code compiler folds the literal `-0` to `+0`** (R 4.5.2): `compiler::cmpfun(function() 1/c(0, -0))()` is `Inf Inf`. The cross-platform fixture's negative zero had silently become positive zero inside a JIT-compiled helper, and the encoder was blamed until `1/v` was checked. Test values make `-0` at run time (`neg_zero()`).
- **All 65,536 half-precision patterns round-trip** through `zu_half_to_double()` and the encoder's width selection (`zucbor_half_roundtrip()`, a test hook). Float width selection is project code, as §8 planned.
- **Depth is charged identically in both directions.** A test that nests six kinds of leaf (scalar, `POSIXct`, tag, named vector, `cbor_map`, bignum) at depths 1–4 checks that `cbor_encode(max_depth = 4)` succeeds exactly when `cbor_validate(max_depth = 4)` accepts the result. Tags written for `POSIXct`, `Date` and wide bignums count as levels, which the first version of the encoder forgot.
- **`zu_raise_fault()` must not use `do.call()`.** It was briefly rewritten with `do.call()` to add an `arg` field, and `do.call()` evaluates a language object passed as an argument. That re-ran the user's own call inside the error handler, and failed as "object 'x' not found" or as C stack overflow. The condition is now built directly, which is the R-side twin of the `quote()` the C side already uses.
- A checked-in 645-byte encoding of a value exercising every encoder path is compared byte for byte on every CI platform. Under `gctorture(TRUE)` 82 values encode identically, and the local UBSan build with `-UNDEBUG` is clean over the suite and an exerciser that now drives the encoder too.

---

## Stage 5 — Diagnostic notation · S

**Status:** complete.

**Do**
- ~~`src/zu_diag.c`: the `CborStreamFunction` callback over `cborpretty.c`~~ a project printer instead (see below), formatting into `R_alloc` scratch, the result copied into one CHARSXP.
- `cbor_diagnose()` runs the check phase first, so the pretty-printer never sees input the walk refused, and its output is bounded by a constant multiple of `max_size`.
- `print` methods for the value classes use diagnostic notation where it is clearer.

**Exit**
- Appendix A's diagnostic column matches for every example, or each difference is listed with the reason (TinyCBOR's spelling of floats and indefinite lengths differs in places).
- Windows output identical to Linux for 64-bit integers (trap 5).

**What actually happened**

- **TinyCBOR's printer could not meet the exit criterion,** so it was replaced. `cborpretty.c` always marks a float's width, as `1.5f16` or `1.5_1`, and has no flag to leave the mark out, while Appendix A writes `1.5`. `src/zu_diag.c` is a project printer over the checked input, about the same size as the callback glue it replaced. `cborpretty.c` left the vendored subset through `tools/update-tinycbor`, and trap 5 lost its main reason.
- **79 of 81 Appendix A rows match the RFC's own column exactly.** That holds once numbers follow JavaScript's `toString()` rule plus `.0` (`0.00006103515625`, `5.960464477539063e-8`, `1.0e+300`) and text is ASCII with `\u` escapes and surrogate pairs (`"\ud800\udd51"`). The other two are bignums, whose value the table prints where the notation is the tag.
- **A `printf` tie missed the shortest form of 2^-24.** 2^-24 is exactly `5.9604644775390625e-8`. At 16 significant digits `printf` rounds that tie to even, giving `…062`, which reads back as the neighbouring double. The shortest correct form is `…063`, so the first version printed 17 digits. Each precision now also tries both neighbours of `printf`'s answer. A test hook checks 20,000 random doubles and the edge cases read back bit-exactly through the C library's `strtod()`, since R's parser cannot be trusted for that on arm64 (Stage 3).
- **The same printer names non-text keys** under `map_keys = "string"`, which retired Stage 3's float-key special case: one formatter, two uses.

---

## Stage 6 — Conformance and real-world corpus · M

**Status:** complete.

**Do**
- `tools/run-conformance` against `cbor/test-vectors` at a pinned commit: decode every vector; for each with `roundtrip: true`, encode and compare bytes. A baseline per category of known difference, attributed by rule, not by a list of file names, so a new deviation cannot hide in a known one (`zuxml`'s W3C harness).
- Fixture corpus in `tests/testthat/fixtures/`, small and licensed for redistribution: `cose-wg/Examples` messages, RFC 8392 CWTs, WebAuthn Level 3 test vectors, RFC 8428 SenML packs. Record each source and licence in the fixture directory.
- One test per fixture asserting the specification's stated values, not a snapshot of our own output.

**Exit**
- Conformance run at zero unexplained deviations, and seen to fail when a baseline is lowered or an entry removed.
- Every fixture decodes; every deterministic fixture round-trips byte-for-byte.

**What actually happened**

- **The corpus is larger than planned.** On the user's question of which suites would harden testing, QCBOR's 122 not-well-formed vectors (BSD-3-Clause) were added to the plan, and all of `cose-wg/Examples` was taken instead of a sample. That is 306 messages plus the 345 structures their signatures and MACs cover. `tools/update-fixtures` regenerates every fixture from its pinned source in about three seconds, so the fixtures are data with provenance, not hand-copied hex.
- **Results.**
  - All 122 QCBOR vectors are `zucbor_parse_error`.
  - All 651 COSE items validate.
  - **Every one of the 345 signed or MACed structures re-encodes to exactly the bytes that were signed.** That is the property COSE verification depends on, and the strongest real-world evidence for the deterministic encoder.
  - Of the 306 messages, the 179 in deterministic form round-trip exactly. The other 127 all fail on one thing, map keys out of bytewise order, and those are exactly the ones that do not round-trip. "Deterministic ⇒ fixed point" held across 524 real items without exception.
  - All 15 WebAuthn attestation objects round-trip, and each credential key's COSE `kty` and `alg` match the IANA registry for its section, from ES256 (−7) to Ed448 (−53).
  - The CWT claims set decodes to exactly the claims RFC 8392 prints.
- **Our diagnostic notation matches cose-wg's on 304 of 306 messages.** The two exceptions are errors in cose-wg's own examples: `x509-examples/signed-01` and `-02` show the `kid` as a byte string in their notation, while their hex encodes it as text. The hex is what was signed, and COSE requires a byte string, so it is the hex that is wrong. `fixtures/README.md` records it.
- **QCBOR's test data has a latent overread.** Two vectors declare 6 bytes and list 4, so QCBOR's own test reads 2 bytes past its array, and a third declares 2 and lists 4. The fixture keeps what QCBOR's test actually reads. Neither upstream has been told yet.
- **The suite had grown to 20 s,** mostly testthat's per-expectation overhead on thousands of `expect_error()` calls. Bulk checks now compute every outcome, then assert once with the failing inputs named (`fault_class()`). The suite is back to about 7 s.
- **gctorture had stalled on Stage 3's PR.** The interrupt test's 4-million-item decode means hours of collections under `gctorture2(step = 100)`, and it tests an unwind path, not PROTECT discipline. The two allocation-heavy tests skip when `ZUCBOR_SKIP_HEAVY` is set, which the gctorture job sets, as r-actions advises. gctorture now runs at the quick step on pull requests and at step 100 after merge.
- `tools/run-conformance` runs `cbor/test-vectors` itself with rule-attributed causes and baselines. It was seen to fail with a baseline lowered and with a cause's rule removed. It runs as the `conformance` job in `native-checks.yaml`.

---

## Stage 7 — Hardening · L

**Status:** complete, apart from the cumulative 24 h of fuzzing, which the nightly job accrues on the cached corpus (30 minutes a night).

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

**What actually happened**

- **The check phase was made R-free, not the whole C layer.** The design wanted `fuzz_roundtrip` and `fuzz_diag` through "an R-free harness over the same C code", but build, encode and diagnose all make SEXPs. The check phase used R in only three places: scratch memory, interrupts and a missing offset. Those became hooks in `zu_check.h`, so `zu_walk.c` builds with `-DZU_STANDALONE` against an arena, byte-for-byte the code the package runs. That is the phase hostile input meets first. The R-bound phases are fuzzed through R (`tools/sanitizer-exercise.R`, the property tests), which design §16 now says.
- **The fuzz target asserts more than "no crash".** Relaxing any option must never reject what the stricter setting accepted, and a check that passes must report exactly one item outside a sequence and no container count larger than the input. Apple's clang has no libFuzzer, so locally the target was built with ASan and UBSan and a file-driven `main()`. It replayed the 1,320-seed corpus and 30,000 random mutations of it clean, with every invariant holding. The canary crashed on the first valid seed.
- **Every guard is load-bearing, and one guards memory too.** The mutation check disables eight guards in turn: items, duplicate keys, container depth, tag depth, length headers, bignum form, tag content, trailing bytes. Each hostile input's answer changes. Removing the container-depth guard makes the probe *abort*: the walk's container stack is sized from `max_depth`, so the limit check is what keeps it in bounds. The ninth marker, `odd-map`, is not probed: TinyCBOR already refuses a break in a map's value position, so nothing reaches it, and the script says so rather than claiming it.
- **The mutation script was first seen to do nothing.** The duplicate-key guard's line ends in `{`, the first sed pattern did not match it, and the "mutant" was the original. It passed, vacuously. The script now refuses to continue when a mutant equals the original. The same lesson as zuxml's lint gate, learnt again.
- **Lint's only finding was R's registration idiom.** With `-Wextra`, clang rejects `(DL_FUNC) &f`, which is exactly what Writing R Extensions prescribes. `init.c` alone gets `-Wno-cast-function-type`. Everything else, the standalone build included, is clean under `-Wall -Wextra -Wpedantic -Wshadow -Werror`.
- **rchk found three things in Stage 4's encoder** while these stages were stacked: an attribute held across allocations in `as_is()` and in `encode()`, and a PROTECT inside a two-pass loop it could not balance. They were fixed on Stage 4's branch, and Stages 5–7 were rebased onto it.
- `.covrignore` excludes the vendored sources, so the coverage badge reports project code.

---

## Stage 8 — Documentation, benchmarks, CRAN prep · M

**Status:** complete.

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

**What actually happened**

- **The first benchmark missed every §17 target by a lot.** Decoding took 3.4–4.5× zujson's time, encoding 1.7–3.3×, and the check phase was 40 % of decoding. Six causes were found by reading the code against the numbers, and each fix was re-measured:
  - a second validation pass only for UTF-8;
  - an allocation per map for duplicate-key sorting;
  - a copy of every text string;
  - a throwaway vector per map key;
  - an R object per scalar array element;
  - an encoder measuring pass.
- **Where that left the numbers.** Decoding reached 1.7–2.2× and encoding 0.95–1.3×. The remaining decode gap is the check-before-build design, plus yyjson's speed, so design §17 now records the measurements and revised targets. That follows zuxml's precedent of documenting a gap with its measured reason rather than gating on an aspiration.
- **The fixes were side effects worth having on their own.** UTF-8 moved into the walk, so UTF-8 faults gained byte offsets (§19 Q4 closed) and a new `utf8` guard joined the mutation check. The encoder's output buffer is `malloc()` memory owned by a finalized external pointer: the family's memory rule applied for the first time in this package, since until then everything had been `R_alloc()`.
- **`-Wshadow` found three shadowed locals** as soon as the lint gate of Stage 7 ran over these changes: two in Stage 5's rewritten exponent formatter and one in Stage 8's already-sorted check. The exponent formatter itself was rewritten because GCC's `-Wformat-truncation` could not prove an `snprintf()` safe, which R CMD check on Linux raises to a WARNING. R 4.6's own `R_ext/Boolean.h` fails `-Wpedantic` under gnu17, so the gate passes R's headers as `-isystem`.
- **Stacked pull requests need retargeting before the base branch is deleted.** Merging Stage 3 with `--delete-branch` closed Stage 4's PR rather than retargeting it. The branch was restored, the PR reopened and pointed at `main`, and later merges retarget first.
- Two vignettes ship: *Decoding untrusted CBOR*, and *COSE and WebAuthn*, which decodes a WebAuthn attestation object, its COSE_Key and an RFC 8392 CWT, and builds the `Sig_structure` a verifier signs over. A getting-started article is pkgdown-only. The README is rewritten, and states the GCC ≥ 11 requirement (decision 23).
- `R CMD check --as-cran --run-donttest` is 0/0/0 at version 0.1.0, and `pkgdown::check_pkgdown()` finds no problems.

---

## Stage 9 — First CRAN release · S

**Status:** open. The acceptance criteria are verified below; tagging `v0.1.0` and submitting to CRAN remain, deliberately a human step.

- Verify each §20 acceptance criterion explicitly, in a table naming the test file, tool or CI job behind it. Writing it out is the check: `zuxml` found three criteria backed only by gates nothing else mentioned.
- Tag `v0.1.0`, submit, respond. A human step.
- 0.1.0, not 1.0.0: no consumer has used the API yet, and CRAN version numbers only go up.

**Acceptance criteria (design §20), each with what verifies it** (2026-09-30):

| # | Criterion | Verified by |
|---|---|---|
| 1 | Builds from source on Windows, macOS and Linux (release, devel, oldrel), no system library, CMake or autotools | `R-CMD-check.yaml` full profile: macOS, Windows and Ubuntu release, Ubuntu oldrel-1, R-devel containers (GCC 16; clang 23 with `-std=gnu23`), Ubuntu clang |
| 2 | No R object is allocated before the check phase has passed | Structural: the check phase (`zu_walk.c`) compiles with no R headers at all (`-DZU_STANDALONE`, the fuzz build), so it *cannot* allocate an R object. Behavioural: `test-limits.R`, a nine-byte header claiming 2^64 − 1 elements and a `max_items` flood, both refused |
| 3 | Every oversized, deep, truncated or malformed input fails through a classed `zucbor_error` with its status; none crashes, hangs or reaches R's allocator unbounded | `test-validate.R` (every Appendix F example; all 426 truncations of Appendix A), `test-conformance.R` (QCBOR's 122 vectors), `test-limits.R`; libFuzzer's `fuzz_check` under ASan and UBSan (`hardening.yaml`); `tools/sanitizer-exercise.R` in the ASan containers; `tools/run-mutation-check` |
| 4 | Duplicate keys are rejected by value by default | `test-duplicate-keys.R`, every comparison class (`1` against `0x1801`, half against double `1.0`, chunked against definite strings); the `duplicate-keys` mutation case |
| 5 | Encoding is deterministic: byte-identical across calls, sessions and platforms, and accepted by `cbor_validate(deterministic = TRUE)` | `test-encode.R`, a checked-in 645-byte encoding compared on every CI platform; `test-roundtrip.R`, 300 generated values each encoded twice and validated deterministic |
| 6 | RFC 8949 Appendix A passes in both directions; every Appendix F example is rejected | `test-decode.R` (every Appendix A value, `identical()`), `test-roundtrip.R`, `test-diagnose.R` (the RFC's own diagnostic column, 79 of 81 exactly, the bignum rows explained), `test-validate.R`; `tools/run-conformance` over `cbor/test-vectors` itself |
| 7 | Every documented mapping row has a test, and the three copies of each table agree | `test-decode.R`, `test-encode.R` and `test-classes.R` against the tables in `?cbor_decode`, `?cbor_encode` and design §6–§7. Agreement of the three copies is checked by review, not by a tool |
| 8 | The §16 round-trip properties hold across the corpus | `test-roundtrip.R`; `test-conformance.R`: all 524 deterministic items in the COSE, CWT and WebAuthn corpora re-encode byte-exactly, including every signed or MACed structure |
| 9 | Fuzzing under ASan and UBSan finds nothing in project code over a sustained run; the gate has been seen to fail on its canary | `tools/run-fuzz` requires `fuzz_canary` to crash first; runs of 2 minutes per pull request and 30 minutes nightly accumulate on a cached corpus. *Sustained* is met only as the nightly hours accrue; the local replay of 30,000 mutations was clean |
| 10 | Vendored TinyCBOR provenance is recorded and `tools/verify-vendor` reproduces the tree | `src/vendor/PROVENANCE`, `inst/COPYRIGHTS`, `LICENSE.note`; `tools/verify-vendor` in `vendor.yaml`, seen to fail on a one-byte edit |
| 11 | `R CMD check --as-cran` is clean on all three platforms, with no stdio or abort symbols in the shared object | CI matrix; `tools/check-symbols` in `vendor.yaml`, seen to fail on a planted `fprintf(stderr, ...)` |
| 12 | The COSE, CWT and WebAuthn fixtures decode to the values their specifications state | `test-conformance.R`: the RFC 8392 claims set exactly; each WebAuthn credential key's `kty` and `alg` against the IANA registry; cose-wg's own diagnostic notation on 304 of 306 messages, the two others being errors in the examples |

Writing it out found one criterion (7) that nothing checks mechanically, and one (9) met only as far as the nightly fuzzing has run. Both are stated as such rather than claimed.

**What remains, and is yours:** tag `v0.1.0` on `main`, submit to CRAN (`devtools::submit_cran()`), and respond to the reviewers. `cran-comments.md` is ready.

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
