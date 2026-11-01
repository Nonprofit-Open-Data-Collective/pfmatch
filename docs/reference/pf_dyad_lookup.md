<div id="main" class="col-md-9" role="main">

# Look up the dyad class for pairs of EINs

<div class="ref-description section level2">

Vectorised and order-insensitive. Returns `NA` where no direct edge
exists — and only a direct edge counts, by design (see
[pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md)).

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_dyad_lookup(dyads, a, b, what = c("class", "id"))
```

</div>

</div>

<div class="section level2">

## Arguments

-   dyads:

    Output of `pf_build_dyads()`.

-   a, b:

    Character vectors of EINs, recycled to a common length.

-   what:

    `"class"` (default) or `"id"`.

</div>

<div class="section level2">

## Value

A character vector.

</div>

</div>
