# The grants-paid variables, taken from concordance990

Reads the variable names from the installed concordance rather than
hardcoding them, so a concordance rename surfaces here instead of
silently producing all-missing columns. Falls back to the names baked
into
[`pf_efilepf_map()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_map.md)
when concordance990 is not installed.

## Usage

``` r
pf_concordance_vars(check = TRUE)
```

## Arguments

- check:

  When `TRUE` and concordance990 is installed, warn about any name
  pfmatch expects that the concordance no longer lists.

## Value

A character vector of concordance990 v2 variable names.
