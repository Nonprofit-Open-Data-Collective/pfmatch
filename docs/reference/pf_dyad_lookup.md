# Look up the dyad class for pairs of EINs

Vectorised and order-insensitive. Returns `NA` where no direct edge
exists — and only a direct edge counts, by design (see
[pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md)).

## Usage

``` r
pf_dyad_lookup(dyads, a, b, what = c("class", "id"))
```

## Arguments

- dyads:

  Output of
  [`pf_build_dyads()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_dyads.md).

- a, b:

  Character vectors of EINs, recycled to a common length.

- what:

  `"class"` (default) or `"id"`.

## Value

A character vector.
