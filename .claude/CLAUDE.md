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

The plan is written: [.agents/design.md](../.agents/design.md) is the specification (numbered §1–§20: the R mapping in §6–§7, deterministic encoding §8, errors §10, limits §11, TinyCBOR vendoring and its build traps §13, open questions §19) and [.agents/roadmap.md](../.agents/roadmap.md) sequences it into Stages 0–9, each with a **Status:** line. Progress is tracked in the `v0.1.0` milestone: umbrella issue #4, with one `stage` sub-issue per stage (#5 for Stage 0 through #14 for Stage 9), each linking to its heading anchor. Never put status in a stage heading, since that changes the anchor. Read both before starting work; a decision in design §18 is settled unless the work shows it is wrong, and then the design changes in the same commit.

Stages 0–8 are done, and the next release is planned in [.agents/roadmap-0.2.0.md](../.agents/roadmap-0.2.0.md) (Stages 10–16, from a survey of Python's and Node's CBOR libraries). `main` carries `0.0.0.9000`, the never-released development version; Stage 9's remaining steps are a human's: set `Version: 0.1.0` and the `NEWS.md` heading, tag `v0.1.0`, submit to CRAN, answer reviewers. The roadmap's Stage 9 table maps each design §20 acceptance criterion to what verifies it.

**API:** `cbor_decode()`/`cbor_decode_seq()`, `cbor_read()`/`cbor_read_seq()`, `cbor_validate()`, `cbor_diagnose()`, `cbor_encode()`/`cbor_encode_seq()`, the value classes `cbor_map()`, `cbor_tag()`, `cbor_simple()`, `cbor_bigint()`, the `as_cbor()` generic, and `zucbor_info()`. The decoders take `tag_handlers =` (design §6.6, §7.5). Work after 0.1.0 follows `.agents/roadmap-0.2.0.md`.

**Architecture** (design §4):

- *Vendored:* only TinyCBOR 7.0's parser, validator and error strings, in `src/vendor/tinycbor/`, byte-identical (`tools/verify-vendor`, run by the `vendor` workflow). The two headers upstream generates at CMake time are written by `tools/update-tinycbor` into the project-owned `src/tinycbor/`. The encoder (`src/zu_encode.c`, design §8) and the diagnostic printer (`src/zu_diag.c`, design §5) are project code.
- *Check phase* (`src/zu_walk.c`), which is all of `cbor_validate()`: one iterative walk for limits, duplicate keys (by value, sorted per map), UTF-8, tag content and offsets. `cbor_value_validate()` runs only for `deterministic = TRUE`. It returns a fault to R, which raises it with the user's call (`zu_raise_fault()`); status names map to classes in `zu_status_class` (`R/conditions.R`), and `tools/check-status-table` keeps the C table (`src/zu_status.c`) equal to `cbor.h`.
- *Build phase* (`src/zu_build.c`): runs only after the check, takes container sizes from the check's plan (never from length headers), stages scalar array elements in C, and raises its own faults through `zu_raise_fault()` via `R_FindNamespace`, with the user's call wrapped in `quote()`. `zu_mkchar()` there is the only place CBOR text becomes a CHARSXP.

**Invariants that are easy to break:**

- The check phase (`zu_walk.c`, `zu_status.c`, `zu_float.c`) is R-free behind `src/zu_check.h`: use `zu_scratch()`, `zu_interrupt_check()` and `ZU_NO_OFFSET` there, never `R_alloc()` or R headers, or the fuzz build (`-DZU_STANDALONE`) breaks.
- Security guards in the walk carry a `/* GUARD: name */` marker on their `if` line; `tools/run-mutation-check` proves each is load-bearing. Add a case there for any new guard.
- Do not switch on `CborValidateTagUse`: TinyCBOR's table refuses valid tag 1 floats (design §3, §11).
- Three decoder rules make `cbor_encode(cbor_decode(b))` equal `b` and are pinned by `test-roundtrip.R` and the COSE corpus: a one-element array decodes as an `I()` value, booleans do not join the numbers, and whole doubles encode as integers.
- The encoder writes into a `malloc()` buffer owned by a finalized external pointer (and each non-text map key into one of its own): the only heap memory that crosses a longjmp.
- User code runs mid-build (tag handlers, via `zu_run_handler()`) and mid-encode (`as_cbor()` methods): it may error, be interrupted, or call zucbor again, so the build and the encoder keep no static state and hold everything `PROTECT`ed or `R_alloc()`ed. Scratch allocated after a `vmaxget()` mark dies at its `vmaxset()`: never keep a pointer to it past that (the encoder's map pools did, until Stage 10).
- `zu_raise_fault()` builds its condition directly: `do.call()` would evaluate the user's call again.
- `src/init.c` registers every `.Call` entry point (`R_useDynamicSymbols(dll, FALSE)`, `R_forceSymbols(dll, TRUE)`), so R code calls `.Call(zucbor_x)`, never `.Call("zucbor_x")`.

**Tests:**

- Float literals are built from bits (`f64()`, `f32()` in `helper-expect.R`), because R's parser on macOS arm64 does not round every decimal literal correctly.
- `-0` is made at run time, because the byte compiler folds the literal to `+0`.
- Checking many inputs goes through `fault_class()` and one expectation, since per-expectation overhead dominates run time.
- Tests that allocate millions of objects call `skip_heavy()`; the gctorture job sets `ZUCBOR_SKIP_HEAVY`.
- Third-party conformance data in `tests/testthat/fixtures/` is regenerated only with `tools/update-fixtures`, never by hand. `tools/run-conformance` checks it against its sources and runs `cbor/test-vectors` against rule-attributed baselines.
- Performance: `tools/run-benchmarks` against zujson (design §17). Re-run it after changing the walk, the builder or the encoder.

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
- `pkgdown.yaml` builds the site and deploys `docs/` to `gh-pages` (https://pedrobtz.github.io/zucbor/). `_pkgdown.yml` sets `development: mode: auto`, which decides from the version: `0.0.0.9000` (never released, now) builds at the root marked *unreleased*; a release (`0.1.0`) builds at the root; a later development version (`0.1.0.9000`) builds into `dev/`, and the deploy keeps both (`clean: false`). So after each CRAN release, bump `main` to `x.y.z.9000` (with a matching `NEWS.md` heading).
- `vendor.yaml`: the vendored-tree guard, the shared-object symbol check and the status-table check.
- `native-checks.yaml`: UBSan and ASan (with `-UNDEBUG`), valgrind, LTO, gctorture (quick step on PRs), a blocking `rchk`, and the `conformance` job.
- `hardening.yaml`: `tools/run-lint`, `tools/run-mutation-check`, `tools/check-no-network`, and `tools/run-fuzz` (libFuzzer, canary first; 2 minutes per PR, 30 nightly on a cached corpus). Apple's clang has no libFuzzer.

This file lives in `.claude/`, not the package root, because pkgdown renders every root-level `*.md` as a site page; keep it here.

Stacked pull requests: retarget the next PR to `main` *before* deleting a merged base branch; deleting it first closes the dependent PR.

## Conventions carried over from the sibling packages

These are how `zujson`/`zuxml` are built; follow them here unless there is a CBOR-specific reason not to.

- **Vendored sources are never edited in place.** They live under `src/vendor/<lib>/`, byte-identical to a pinned upstream release, refreshed by a script in `tools/`. Local configuration goes in a project-owned header outside the vendor tree.
- **Portable make only** in `src/Makevars`: list object files in `OBJECTS` by hand (R only auto-compiles `src/*.c`, not subdirectories), and no GNU-make features such as `$(wildcard)` or `$(shell)`, which would cost `SystemRequirements: GNU make`. There is deliberately no `Makevars.win`; Windows falls back to `Makevars`, so there is one list to keep right. Keep `.o`/`.so`/`.dll` out of the build tarball via `.Rbuildignore`.
- **Naming:** R exports use the format prefix `cbor_` (as `json_`/`xml_` in the siblings), plus `zucbor_info()` and the `as_cbor()` generic; R and C internals use `zu_`, `.Call` entry points use `zucbor_`, condition classes `zucbor_`, and user-facing value classes `cbor_`.
- **Errors are classed conditions**, all inheriting a package base class (e.g. `zujson_error`), raised in C where the cause is known. Tests assert on condition class, never message text.
- **Heap state that must survive a longjmp is owned by R** (finalized external pointers), since `Rf_error()`, `R_CheckUserInterrupt()` and R allocators jump past any `free()`.
- **Tests are self-sufficient** (inputs built inside each `test_that()`), pass under `shuffle = TRUE`, stay serial (no `Config/testthat/parallel`, so gctorture/valgrind CI legs actually exercise the C code), and keep the suite to a few seconds for CRAN.
- **Prose is en-GB** (`Language: en-GB` in DESCRIPTION in the siblings), with domain terms in `inst/WORDLIST` via `spelling::update_wordlist()`.
- Design documents live in `.agents/`. Keep design.md's mapping tables in sync with the roxygen docs and the tests: they are the same table three times.
