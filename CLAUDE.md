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

Stage 0 is done: `DESCRIPTION` and the licence files are real, `NEWS.md` has a versioned heading (R CMD check NOTEs a bare `# zucbor (development version)` once it is the only heading, so keep it versioned), and `tests/testthat/test-init.R` replaces the template test. `README.md` is still the template (Stage 8), there is no R API, and TinyCBOR is not vendored yet (Stage 1). `src/init.c` registers the DLL with an empty `.Call` table; each new entry point goes in that table (`@useDynLib zucbor, .registration = TRUE` with `R_useDynamicSymbols(dll, FALSE)`, so an unregistered symbol is not callable).

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
- **Portable make only** in `src/Makevars`: list object files in `OBJECTS` by hand (R only auto-compiles `src/*.c`, not subdirectories), and no GNU-make features such as `$(wildcard)` or `$(shell)`, which would cost `SystemRequirements: GNU make`. Keep `Makevars.win` in step. Keep `.o`/`.so`/`.dll` out of the build tarball via `.Rbuildignore`.
- **Naming:** R exports use a format prefix (`json_parse`/`xml_parse` → here presumably `cbor_*`), R and C internals use `zu_`, `.Call` entry points use `zucbor_`.
- **Errors are classed conditions**, all inheriting a package base class (e.g. `zujson_error`), raised in C where the cause is known. Tests assert on condition class, never message text.
- **Heap state that must survive a longjmp is owned by R** (finalized external pointers), since `Rf_error()`, `R_CheckUserInterrupt()` and R allocators jump past any `free()`.
- **Tests are self-sufficient** (inputs built inside each `test_that()`), pass under `shuffle = TRUE`, stay serial (no `Config/testthat/parallel`, so gctorture/valgrind CI legs actually exercise the C code), and keep the suite to a few seconds for CRAN.
- **Prose is en-GB** (`Language: en-GB` in DESCRIPTION in the siblings), with domain terms in `inst/WORDLIST` via `spelling::update_wordlist()`.
- Design documents live in `.agents/`. Keep design.md's mapping tables in sync with the roxygen docs and the tests: they are the same table three times.
