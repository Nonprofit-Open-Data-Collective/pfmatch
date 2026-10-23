# Flag grant rows whose recipient is a pointer to an attachment

Flag grant rows whose recipient is a pointer to an attachment

## Usage

``` r
pf_is_placeholder(grants, name_col = "recip_name")
```

## Arguments

- grants:

  A prepared frame from
  [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md).

- name_col:

  Column holding the recipient name.

## Value

A logical vector.
