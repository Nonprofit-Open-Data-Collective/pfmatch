# Standardize SIGOCPYRFSTA into recipient types

Applies the rule cascade documented in
[pf_recipient_type](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recipient_type.md).

## Usage

``` r
pf_standardize_status(x)
```

## Arguments

- x:

  Character vector of raw `SIGOCPYRFSTA` values.

## Value

A data frame with one row per input value:

- `recipient_type`:

  the five-level standard, as a factor with levels from
  [`pf_type_levels()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_type_levels.md)

- `recipient_type_detail`:

  the finer level that drives scope

- `status_norm`:

  the normalized string the rules matched against

- `status_rule`:

  index of the rule that fired; `NA` if none did
