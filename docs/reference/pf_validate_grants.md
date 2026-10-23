# Validate a grant file

Checks schema consistency, key uniqueness, deduplication status and
column coverage, and reports what it finds rather than guessing at a
repair.

## Usage

``` r
pf_validate_grants(grants, strict = FALSE, verbose = TRUE)
```

## Arguments

- grants:

  A grant frame, or a path passed to
  [`pf_read_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_read_grants.md).

- strict:

  When `TRUE`, any FAIL raises an error instead of returning.

- verbose:

  Print the report.

## Value

A `data.frame` of checks, one row per check, with columns `check`,
`status` (`PASS` / `WARN` / `FAIL` / `INFO`) and `detail`, invisibly.
