<div id="main" class="col-md-9" role="main">

# Geographic-agreement diagnostics

<div class="ref-description section level2">

How often the address the foundation typed agrees with the BMF address
of the organization it matched to. The point of running the cascade
state-free is to measure this before deciding whether a geographic block
is safe.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_geo_agreement(status)
```

</div>

</div>

<div class="section level2">

## Arguments

-   status:

    A frame from `pf_status()`, or a `pf_match`.

</div>

<div class="section level2">

## Value

A one-row-per-outcome data frame of state / ZIP agreement rates.

</div>

</div>
