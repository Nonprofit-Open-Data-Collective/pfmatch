# Summarise a dyad table

Reports size, class split, and the degree distribution of the
substitutable subgraph — the last being the number that says whether the
table is safe to collapse on. A maximum substitutable degree above about
ten means a federated network has leaked in; see
[pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md).

## Usage

``` r
pf_dyad_summary(x)
```

## Arguments

- x:

  Output of
  [`pf_build_dyads()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_dyads.md).

## Value

`x`, invisibly.
