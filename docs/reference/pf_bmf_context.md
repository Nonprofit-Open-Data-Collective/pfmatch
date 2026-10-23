# Build a compact BMF context table keyed by EIN

Build a compact BMF context table keyed by EIN

## Usage

``` r
pf_bmf_context(bmf, prefix = "BMF_")
```

## Arguments

- bmf:

  The raw processed BMF (data frame or CSV path).

- prefix:

  Column prefix for the returned fields.

## Value

A `data.table` keyed by `ein`.
