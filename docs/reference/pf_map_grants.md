<div id="main" class="col-md-9" role="main">

# Schema map from prepared grant columns onto npmatch canonical fields

<div class="ref-description section level2">

Use as the `query_map` argument of `npmatch::np_cascade()`. Operates on
the output of `pf_prepare_grants()`, not the raw extract.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_map_grants()
```

</div>

</div>

<div class="section level2">

## Value

A named character vector, `canonical_field = prepared_column`.

</div>

</div>
