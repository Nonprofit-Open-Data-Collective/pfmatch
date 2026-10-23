# Outcome x recipient-type crosstab

Outcome x recipient-type crosstab

## Usage

``` r
pf_crosstab(status, pct = TRUE)
```

## Arguments

- status:

  A frame from
  [`pf_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_status.md),
  or a `pf_match`.

- pct:

  If `TRUE`, add row-percentage columns.

## Value

A data frame: one row per recipient type, one column per outcome.
