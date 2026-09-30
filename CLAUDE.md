# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zucbor` is an R package that encodes and decodes CBOR (RFC 8949) to and from ordinary R vectors and lists, using a **vendored copy of the TinyCBOR C library** so no system library is required. CBOR is JSON's binary counterpart — maps, arrays, strings, numbers, booleans, null — plus native byte strings, exact 64-bit integers, and semantic tags (dates, bignums, UUIDs).

Intended properties that should shape every design decision:

- **Decoding** accepts raw vectors, files and connections; **validates structure before building any R object**; and enforces configurable depth and size limits, because the input is expected to be untrusted (network, IoT devices).
- **Encoding is deterministic**: identical R objects produce identical bytes.
- Target uses: COSE and WebAuthn passkey data, CWT tokens, CoAP device telemetry, and other IETF protocols that moved from JSON to CBOR.
- It is the fourth self-describing format in a family with `zujson`, `zuyaml` and `zuxml` (sibling checkouts in `../`). When a design question is not answered here, look at how those packages settle it before inventing something new — `../zujson/CLAUDE.md` and `../zuxml/CLAUDE.md` are the most detailed.

## Current state

The plan is written: [.agents/design.md](.agents/design.md) is the specification (numbered §1–§20: the R mapping in §6–§7, deterministic encoding §8, errors §10, limits §11, TinyCBOR vendoring and its build traps §13, open questions §19) and [.agents/roadmap.md](.agents/roadmap.md) sequences it into Stages 0–9, each with a **Status:** line. Progress is tracked in the `v0.1.0` milestone: umbrella issue #4, with one `stage` sub-issue per stage (#5 for Stage 0 through #14 for Stage 9), each linking to its heading anchor. Never put status in a stage heading, since that changes the anchor. Read both before starting work; a decision in design §18 is settled unless the work shows it is wrong, and then the design changes in the same commit.

Stages 0–8 are done; version 0.1.0 is prepared for Stage 9, the CRAN submission, which is a human step. TinyCBOR 7.0's parser, validator and error strings are vendored in `src/vendor/tinycbor/` (the encoder and printer are project code) (byte-identical; `tools/verify-vendor` proves it, and the `vendor` workflow runs it), with the two headers upstream generates at CMake time written by `tools/update-tinycbor` into the project-owned `src/tinycbor/`. The R API so far is `zucbor_info()`, `cbor_encode()`/`cbor_encode_seq()` (project code in `src/zu_encode.c`, not TinyCBOR's encoder: design §8), `cbor_decode()`/`cbor_decode_seq()`, `cbor_diagnose()` (project printer in `src/zu_diag.c`, matching RFC 8949 Appendix A: design §5), `cbor_read()`/`cbor_read_seq()`, the value classes (`cbor_map()`, `cbor_tag()`, `cbor_simple()`, `cbor_bigint()`) and `cbor_validate()`, which is the whole check phase (`src/zu_walk.c`): an iterative walk for limits, duplicate keys (by value, merge-sorted per map), tag content and offsets, then `cbor_value_validate()` for UTF-8 and deterministic encoding. The walk returns a fault to R, which raises it with the user's call (`zu_raise_fault()`); status names map to classes in `zu_status_class` (`R/conditions.R`), and `tools/check-status-table` keeps the C table equal to `cbor.h`. The build phase (`src/zu_build.c`) runs only after the check, takes container sizes from the check's plan (never from length headers), and raises its own faults through `zu_raise_fault()` via `R_FindNamespace`, with the user's call wrapped in `quote()`; `zu_mkchar()` there is the only place CBOR text becomes a CHARSXP. The check phase (`zu_walk.c`, `zu_status.c`, `zu_float.c`) is R-free behind `src/zu_check.h`: use `zu_scratch()`, `zu_interrupt_check()` and `ZU_NO_OFFSET` there, never `R_alloc()` or R headers, or the fuzz build (`-DZU_STANDALONE`) breaks. Security guards there carry a `/* GUARD: name */` marker on their `if` line, which `tools/run-mutation-check` uses to prove each is load-bearing; add a case there for any new guard. `tools/run-lint`, `tools/run-mutation-check`, `tools/check-no-network` and `tools/run-fuzz` (libFuzzer; not available with Apple's clang) run in `hardening.yaml`. Third-party conformance data lives in `tests/testthat/fixtures/` (QCBOR's not-well-formed vectors, all of `cose-wg/Examples`, RFC 8392/8428 and WebAuthn L3 vectors): regenerate it only with `tools/update-fixtures`, never by hand; `tools/run-conformance` checks the fixtures against their sources and runs `cbor/test-vectors` against rule-attributed baselines. Tests that allocate millions of objects call `skip_heavy()`, which the gctorture job triggers through `ZUCBOR_SKIP_HEAVY`; checking many inputs goes through `fault_class()` and one expectation, since per-expectation overhead dominates run time. Performance is measured by `tools/run-benchmarks` against zujson (design §17 has the numbers and targets); re-run it after changing the walk, the builder or the encoder. The encoder writes into a `malloc()` buffer owned by a finalized external pointer: the one place heap memory crosses a longjmp. Three decoder rules exist to make `cbor_encode(cbor_decode(b))` equal `b` and are pinned by `test-roundtrip.R`: a one-element array decodes as an `I()` value, booleans do not join the numbers, and whole doubles encode as integers. Float literals in tests are built from bits (`f64()`, `f32()` in `helper-expect.R`), since R's parser on macOS arm64 does not round every decimal literal correctly, and `-0` is made at run time, since the byte compiler folds the literal to `+0`. `zu_raise_fault()` builds its condition directly: `do.call()` would evaluate the user's call again. Do not switch on `CborValidateTagUse`: TinyCBOR's table refuses valid tag 1 floats (design §3, §11). `src/init.c` registers every `.Call` entry point (`R_useDynamicSymbols(dll, FALSE)`, `R_forceSymbols(dll, TRUE)`), so an unregistered symbol is not callable and R code calls `.Call(zucbor_x)`, never `.Call("zucbor_x")`.

`NEWS.md` keeps a versioned heading: R CMD check NOTEs a bare `# zucbor (development version)` once it is the only heading.

Vendoring checks that must stay green:

```sh
tools/verify-vendor                         # vendor tree == pinned release; generated headers agree
R CMD INSTALL -l <lib> . && tools/check-symbols <lib>/zucbor/libs/zucbor.so
```

Run `tools/check-symbols` on an `R CMD INSTALL` build, not a `load_all()` one: `load_all()` compiles with `-UNDEBUG`, which leaves TinyCBOR's `assert()`s in and makes the check fail, correctly. Under R's normal `-DNDEBUG`, TinyCBOR's `cbor_assert()` becomes `unreachable()`: a violated TinyCBOR precondition is undefined behaviour, not an abort, so check an item's type before calling any `cbor_value_get_*` (design §13, trap 3).

R's own headers need C11 (`R_ext/Complex.h` uses an anonymous struct), so a strict `-std=gnu99 -Wpedantic` build of project files fails inside R, not inside zucbor. Check project files with `-std=gnu17` or later.

No sibling package is a confirmed consumer (roadmap Stage 0 inventory), so v1 is the R API only: no C API, no archive.

roxygen2 must be 8.1.0 or newer (`Config/roxygen2/version` in DESCRIPTION); an older one rewrites `man/` on `document()`.

## Commands

```sh
Rscript -e 'devtools::document()'                  # roxygen -> NAMESPACE + man/
Rscript -e 'devtools::load_all()'                  # compile + load
Rscript -e 'devtools::test()'
Rscript -e 'devtools::test(filter = "init")'       # one file: tests/testthat/test-init.R
Rscript -e 'devtools::test(shuffle = TRUE)'        # order-independence check
Rscript -e 'devtools::check(cran = TRUE)'
Rscript -e 'pkgdown::build_site()'                 # site -> docs/ (gitignored)
```

testthat edition 3; roxygen2 with markdown enabled (`Config/roxygen2/version: 8.1.0`). Never hand-edit `NAMESPACE` or `man/`.

## CI

Workflows in `.github/workflows/` delegate to reusable workflows in `pedrobtz/r-actions@v1`:

- `R-CMD-check.yaml` runs a **quick** profile on each push to a pull request and the **full** profile on pushes to `main`. Adding the `full-ci` label to a PR reruns it with the full profile before merging.
- `coverage.yaml` commits the badge to `.github/badges/coverage.svg` on `main`.
- `pkgdown.yaml` builds the site and deploys `docs/` to `gh-pages` (https://pedrobtz.github.io/zucbor/).

## Conventions carried over from the sibling packages

These are how `zujson`/`zuxml` are built; follow them here unless there is a CBOR-specific reason not to.

- **Vendored sources are never edited in place.** They live under `src/vendor/<lib>/`, byte-identical to a pinned upstream release, refreshed by a script in `tools/`. Local configuration goes in a project-owned header outside the vendor tree.
- **Portable make only** in `src/Makevars`: list object files in `OBJECTS` by hand (R only auto-compiles `src/*.c`, not subdirectories), and no GNU-make features such as `$(wildcard)` or `$(shell)`, which would cost `SystemRequirements: GNU make`. There is deliberately no `Makevars.win`; Windows falls back to `Makevars`, so there is one list to keep right. Keep `.o`/`.so`/`.dll` out of the build tarball via `.Rbuildignore`.
- **Naming:** R exports use a format prefix (`json_parse`/`xml_parse` → here presumably `cbor_*`), R and C internals use `zu_`, `.Call` entry points use `zucbor_`.
- **Errors are classed conditions**, all inheriting a package base class (e.g. `zujson_error`), raised in C where the cause is known. Tests assert on condition class, never message text.
- **Heap state that must survive a longjmp is owned by R** (finalized external pointers), since `Rf_error()`, `R_CheckUserInterrupt()` and R allocators jump past any `free()`.
- **Tests are self-sufficient** (inputs built inside each `test_that()`), pass under `shuffle = TRUE`, stay serial (no `Config/testthat/parallel`, so gctorture/valgrind CI legs actually exercise the C code), and keep the suite to a few seconds for CRAN.
- **Prose is en-GB** (`Language: en-GB` in DESCRIPTION in the siblings), with domain terms in `inst/WORDLIST` via `spelling::update_wordlist()`.
- Design documents live in `.agents/`. Keep design.md's mapping tables in sync with the roxygen docs and the tests: they are the same table three times.
