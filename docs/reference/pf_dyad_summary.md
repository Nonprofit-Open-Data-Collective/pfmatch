<div id="main" class="col-md-9" role="main">

# Summarise a dyad table

<div class="ref-description section level2">

Reports size, class split, and the degree distribution of the
substitutable subgraph — the last being the number that says whether the
table is safe to collapse on. A maximum substitutable degree above about
ten means a federated network has leaked in; see
[pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md).

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_dyad_summary(x)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Output of `pf_build_dyads()`.

</div>

<div class="section level2">

## Value

`x`, invisibly.

</div>

</div>
