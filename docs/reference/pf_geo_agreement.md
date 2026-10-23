# Geographic-agreement diagnostics

How often the address the foundation typed agrees with the BMF address
of the organization it matched to. The point of running the cascade
state-free is to measure this before deciding whether a geographic block
is safe.

## Usage

``` r
pf_geo_agreement(status)
```

## Arguments

- status:

  A frame from
  [`pf_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_status.md),
  or a `pf_match`.

## Value

A one-row-per-outcome data frame of state / ZIP agreement rates.
