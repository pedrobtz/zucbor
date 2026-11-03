# Build information

Reports the bundled TinyCBOR version, the compile-time ceiling on
nesting depth, and the default decoding limits.

## Usage

``` r
zucbor_info()
```

## Value

A list of class `zucbor_info` with elements:

- `tinycbor_version`: version of the bundled TinyCBOR, e.g. `"7.0.0"`.

- `max_depth_cap`: the largest `max_depth` any decoder accepts, set by
  TinyCBOR's compile-time recursion limit.

- `limits`: the default `max_depth`, `max_size` (bytes) and `max_items`.

- `smoke_ok`: `TRUE` if the bundled validator accepts a known-good item.

## Examples

``` r
zucbor_info()
#> <zucbor_info>
#> TinyCBOR:  7.0.0
#> max_depth: 256 (at most 1023)
#> max_size:  67108864 bytes
#> max_items: 1000000
#> self-test: ok
```
