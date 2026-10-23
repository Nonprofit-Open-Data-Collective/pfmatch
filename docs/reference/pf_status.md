# Per-grant outcome frame

Per-grant outcome frame

## Usage

``` r
pf_status(x)
```

## Arguments

- x:

  A `pf_match` from
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

## Value

One row per grant: identity, recipient type, outcome, the chosen EIN and
BMF name, the score and margin, the pass that found it, and the
query/reference geography for the geographic-agreement diagnostics.
