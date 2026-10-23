# Schema map from prepared grant columns onto npmatch canonical fields

Use as the `query_map` argument of
[`npmatch::np_cascade()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_cascade.html).
Operates on the output of
[`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md),
not the raw extract.

## Usage

``` r
pf_map_grants()
```

## Value

A named character vector, `canonical_field = prepared_column`.
