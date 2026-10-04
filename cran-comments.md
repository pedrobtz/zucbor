## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

* GitHub Actions: macOS (R release), Windows (R release), Ubuntu (R release
  and oldrel-1).
* R-hub containers matching CRAN's r-devel-linux-x86_64-debian-gcc (GCC 16)
  and -debian-clang (clang 23, `-std=gnu23`) flavours.
* Native-code checks on every change: ASan and UBSan (gcc and clang),
  valgrind, gctorture, rchk and LTO; libFuzzer on the input checker.

## Tests

The tests take about 15 seconds under `R CMD check`. One, which reads a
million items from a file to show that memory stays bounded, is skipped on
CRAN.

## Bundled code

The package bundles a subset of TinyCBOR 7.0 (MIT licence, Intel
Corporation) in `src/vendor/tinycbor/`, unmodified and verifiable against the
upstream release; provenance is in `src/vendor/PROVENANCE`, and copyright
holders are listed in `Authors@R` and `inst/COPYRIGHTS`.

Building from source needs a C compiler; with GCC, version 11 or newer, since
TinyCBOR 7.0 uses a construct older GCC rejects. Every CRAN check flavour
uses a newer compiler.
