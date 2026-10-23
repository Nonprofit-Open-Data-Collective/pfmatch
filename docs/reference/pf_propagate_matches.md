# Propagate a match back from identities to grant rows

Propagate a match back from identities to grant rows

## Usage

``` r
pf_propagate_matches(grants, status)
```

## Arguments

- grants:

  Output of
  [`pf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup.md).

- status:

  A
  [`pf_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_status.md)
  frame computed over
  [`pf_recipients()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recipients.md).

## Value

`grants` with the identity-level outcome joined onto every row.
