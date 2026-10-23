# Prepare a raw 990-PF grants extract

Prepare a raw 990-PF grants extract

## Usage

``` r
pf_prepare_grants(grants, id_prefix = "G")
```

## Arguments

- grants:

  A data frame of the raw GTDC 990-PF current-grants extract (columns
  `SIGOCPYRPNAM`, `SIGOCPYRBNBN1`, ..., `SIGOCPYRFSTA`).

- id_prefix:

  Prefix for the generated `grant_id` when the input has none.

## Value

A data frame with the original columns plus the prepared recipient name
/ address fields, the standardized recipient type, and the scope
decision (`in_scope`, `oos_reason`).
