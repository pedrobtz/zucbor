# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/native-code.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

zucbor encodes R values as CBOR (RFC 8949) and decodes CBOR and CBOR
sequences (RFC 8742) into ordinary R vectors and lists, through a vendored
subset of TinyCBOR, so no system library is needed. Input is assumed
untrusted (network peers, IoT devices, COSE, WebAuthn, CWT, CoAP): decoding
checks the whole item against depth, size and item limits before building any
R object. Encoding is deterministic: identical R objects give identical bytes
on every platform. Zero hard runtime dependencies. It is the fourth
self-describing format in a family with zujson, zuyaml and zuxml: when the
design does not settle a question, look at how those packages do before
inventing something new.

[`.agents/design.md`](.agents/design.md) is the specification and outranks
this file: the R mapping in §6–§7, deterministic encoding §8, errors §10,
limits §11, TinyCBOR vendoring and its build traps §13, decisions §18, open
questions §19. A decision in §18 is settled unless the work shows it is
wrong, and then the design changes in the same commit.
[`.agents/roadmap.md`](.agents/roadmap.md) records the stages to 0.1.0
(Stages 0–16, all done), each with a **Status:** line. Never put status in a
stage heading, since that changes its anchor.

## Current state

Verified 2026-11-11. 0.1.0 is on CRAN (published 2026-10-21; GitHub release
`0.1.0` on commit `f904184`). `main` is `0.1.0.9000`, with two fixes in
`NEWS.md` so far. The full v1 API is built: the decoders, `cbor_read*()`,
`cbor_validate()`, `cbor_diagnose()`, `cbor_annotate()`, the encoders, the
value classes `cbor_map()`, `cbor_tag()`, `cbor_simple()`, `cbor_bigint()`,
the `as_cbor()` generic and `zucbor_info()`. The roadmap's Stage 9 and
Stage 16 tables map each design §20 acceptance criterion to what verifies it.

## Versions and dependents

The current version's parent issue is
[#56](https://github.com/pedrobtz/zucbor/issues/56) for `v0.1.1`. Its open
sub-issues are #52 (zu-family conventions), #49 (zubin's buffer and cursor)
and #41 (zufast primitives). #57 is the reminder that the next submission
opens from 2026-12-02. Sibling packages that depend on this one: none. No
sibling is a confirmed consumer, so v1 is the R API only, with no C API and
no archive.

## Commands

Occasional, from the package root:

```sh
tools/verify-vendor              # vendor tree == pinned release
R CMD INSTALL -l <lib> . && tools/check-symbols <lib>/zucbor/libs/zucbor.so
tools/check-status-table         # status table == vendored cbor.h
tools/run-lint                   # project C warning-free under strict flags
tools/run-mutation-check         # every GUARD in the walk is load-bearing
tools/run-fuzz [seconds]         # libFuzzer over the R-free check phase
tools/run-conformance            # fixtures vs sources, cbor/test-vectors; network
tools/update-fixtures            # regenerate the conformance fixtures
tools/run-benchmarks             # against zujson (design §17)
tools/update-tinycbor <tag>      # re-vendor TinyCBOR
```

Run `tools/check-symbols` on an `R CMD INSTALL` build, not a `load_all()`
one: `load_all()` compiles with `-UNDEBUG`, which leaves TinyCBOR's
`assert()`s in and makes the check fail, correctly. Re-run the benchmarks
after changing the walk, the builder or the encoder. Apple's clang has no
libFuzzer, so `run-fuzz` needs a clang that ships it.

## Architecture

Two phases (design §4), each in its own file:

- **Check** (`src/zu_walk.c`), which is all of `cbor_validate()`: one
  iterative walk for limits, duplicate keys (by value, sorted per map),
  UTF-8, tag content and offsets. Four modes: one item, a sequence, a prefix,
  and a stream (`cbor_read_seq(each =)`), which stops before an item the
  input ends inside; truncation is `CborErrorUnexpectedEOF` and nothing else,
  which the fuzz target checks. `cbor_value_validate()` runs only for
  `deterministic = TRUE`. The walk returns a fault to R, which raises it with
  the user's call through `zu_raise_fault()`. Status names map to condition
  classes in `zu_status_class` (`R/conditions.R`).
- **Build** (`src/zu_build.c`) runs only after the check, takes container
  sizes from the check's plan (never from length headers), and stages scalar
  array elements in C. It raises its own faults through `zu_raise_fault()`
  via `R_FindNamespace`, with the user's call wrapped in `quote()`.
  `zu_mkchar()` there is the only place CBOR text becomes a CHARSXP.
- **Encoder** (`src/zu_encode.c`, design §8) and **diagnostic printer**
  (`src/zu_diag.c`, §5) are project code; TinyCBOR contributes only its
  parser, validator and error strings.
- `src/init.c` registers every `.Call` entry point
  (`R_useDynamicSymbols(dll, FALSE)`, `R_forceSymbols(dll, TRUE)`), so R code
  calls `.Call(zucbor_x)`, never `.Call("zucbor_x")`.
- `fuzz/` holds the libFuzzer targets, canary, arena and probe; it is not in
  the tarball. The full file list is design §15.

Naming: R exports `cbor_` (plus `zucbor_info()` and `as_cbor()`), R and C
internals `zu_`, `.Call` entry points and condition classes `zucbor_`, and
user-facing value classes `cbor_`, because users construct them.

## Invariants that are easy to break

- **No R object before the whole item is checked.** A nine-byte header can
  claim 2^64 elements; the build may only trust sizes the walk has backed
  with real bytes (design §4).
- **The check phase is R-free** behind `src/zu_check.h` (`zu_walk.c`,
  `zu_status.c`, `zu_float.c`, `zu_time.c`): use `zu_scratch()`,
  `zu_interrupt_check()` and `ZU_NO_OFFSET`, never `R_alloc()` or R headers,
  or the fuzz build (`-DZU_STANDALONE`) breaks.
- **Security guards in the walk carry `/* GUARD: name */`** on their `if`
  line. `tools/run-mutation-check` proves each is load-bearing; add a case
  there for any new guard.
- **Do not switch on `CborValidateTagUse`:** TinyCBOR's table refuses valid
  tag 1 floats (design §3, §11).
- **Check an item's type before any `cbor_value_get_*` call.** Under R's
  `-DNDEBUG`, TinyCBOR's `cbor_assert()` becomes `unreachable()`, so a
  violated precondition is undefined behaviour, not an abort (§13, trap 3).
  The sanitizer jobs build with `-UNDEBUG` to make it visible.
- **Three decoder rules make `cbor_encode(cbor_decode(b))` equal `b`,** pinned
  by `test-roundtrip.R` and the COSE corpus: a one-element array decodes as
  an `I()` value, booleans do not join the numbers, and whole doubles encode
  as integers.
- **The encoder writes into a `malloc()` buffer owned by a finalized external
  pointer** (and each non-text map key into one of its own). It is the only
  heap memory that crosses a longjmp.
- **User code runs mid-build and mid-encode** (tag handlers via
  `zu_run_handler()`, `as_cbor()` methods). It may error, be interrupted or
  call zucbor again, so the build and the encoder keep no static state and
  hold everything `PROTECT`ed or `R_alloc()`ed. Scratch allocated after a
  `vmaxget()` mark dies at its `vmaxset()`: never keep a pointer to it past
  that (the encoder's map pools did, until Stage 10).
- **`zu_raise_fault()` builds its condition directly:** `do.call()` would
  evaluate the user's call again.
- **The design's mapping tables, the roxygen docs and the tests are the same
  table three times.** Change all three together.
- **`NEWS.md` keeps a versioned heading:** R CMD check NOTEs a bare
  `# zucbor (development version)` once it is the only heading.
- **Project files need `-std=gnu17` or later** for strict builds: R's own
  `R_ext/Complex.h` uses an anonymous struct, so `-std=gnu99 -Wpedantic`
  fails inside R, not inside zucbor.
- **roxygen2 must be 8.1.0 or newer;** an older one rewrites `man/` on
  `document()`.
- Prose is en-GB (`Language: en-GB`), with domain terms in `inst/WORDLIST`.

## Testing

- **Conformance:** RFC 8949 Appendix A both ways and Appendix F as
  must-reject (`helper-rfc8949.R`, `helper-rfc8949-diag.R`), QCBOR's 122
  not-well-formed vectors, the cose-wg examples and the spec examples, all in
  `tests/testthat/fixtures/` (sources and licences in its `README.md`).
  Fixtures are regenerated only with `tools/update-fixtures`, never by hand.
  `cbor/test-vectors` runs outside the suite through `tools/run-conformance`,
  against rule-attributed baselines.
- **Helpers** (`helper-expect.R`): `f64()` and `f32()` build float literals
  from bits, because R's parser on macOS arm64 does not round every decimal
  literal correctly. `neg_zero()` makes `-0` at run time, because the byte
  compiler folds the literal to `+0`. `fault_class()` checks many inputs with
  one expectation, since per-expectation overhead dominates run time.
  `expect_cbor()` asserts exact output bytes.
- **Heavy tests** that allocate millions of objects call `skip_heavy()`; the
  gctorture job sets `ZUCBOR_SKIP_HEAVY`.
- **Serial on purpose:** no `Config/testthat/parallel`, so gctorture and
  valgrind see the C code. The suite runs in a few seconds, and no test
  touches the network (`tools/check-no-network`).

## Continuous integration

Shared r-actions workflows at `@v1`: `R-CMD-check.yaml` (quick on a pull
request, full after merge or with `full-ci`) and `coverage.yaml`.
`native-checks.yaml` calls the shared sanitizers (UBSan, and ASan containers
driven by `tools/sanitizer-exercise.R`, both with `-UNDEBUG`), valgrind, LTO,
gctorture (quick on a pull request, step 100 after merge), a blocking rchk,
and runs `tools/run-conformance`; it also runs weekly. `vendor.yaml` calls the
shared vendor check and runs `tools/check-status-table`.

Package-owned: `hardening.yaml` runs `tools/run-lint`,
`tools/run-mutation-check`, `tools/check-no-network` and `tools/run-fuzz`
(2 minutes per target on a pull request, 30 nightly). `pkgdown.yaml` deploys
the site with `development: mode: auto`, so a `.9000` version builds into
`dev/` beside the release.

## Vendored native code

TinyCBOR (`intel/tinycbor`), MIT, tag `v7.0`, commit `6442e749`, imported
2026-09-30, with no local patches. `src/vendor/PROVENANCE` records the tarball
SHA-256 (trust on first use) and the compile configuration;
`tools/tinycbor-files.txt` lists the byte-identical subset (parser, validator,
error strings). The two headers upstream generates at CMake time live in the
project-owned `src/tinycbor/`, written by `tools/update-tinycbor`.
`src/zu_tinycbor_check.c` fails the build if `ZU_MAX_DEPTH_CAP` differs from
`CBOR_PARSER_MAX_RECURSIONS`. There is deliberately no `Makevars.win`, so one
`OBJECTS` list cannot drift. The build traps (C23, MinGW formats, half-float
intrinsics, GCC < 11) are design §13.

## Pull requests

Stacked pull requests: retarget the next one to `main` *before* deleting a
merged base branch; deleting it first closes the dependent pull request.
