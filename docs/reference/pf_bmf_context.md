<div id="main" class="col-md-9" role="main">

# Build a compact BMF context table keyed by EIN

<div class="ref-description section level2">

Build a compact BMF context table keyed by EIN

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_bmf_context(bmf, prefix = "BMF_")
```

</div>

</div>

<div class="section level2">

## Arguments

-   bmf:

    The raw processed BMF (data frame or CSV path).

-   prefix:

    Column prefix for the returned fields.

</div>

<div class="section level2">

## Value

A `data.table` keyed by `ein`.

</div>

</div>
